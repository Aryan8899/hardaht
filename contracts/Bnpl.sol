// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

interface IBnplSubscription {
    struct Subscription {
        uint256 tierId;
        uint32 multiplier;
        uint256 subscriptionFee;
        uint256 maxTradeAmount;
        uint64 start;
        uint64 expires;
        bool isSubscribe;
        bool isDiscount;
        bool isUpgrade;
    }

    function subscriptions(
        address user
    ) external view returns (Subscription memory);

    function getUserMaxTrade(address user) external view returns (uint256);
}

interface ITokenWhitelist {
    function validateTradeToken(address token) external view;
}

interface IBnplVault {
    function transferToken(address token, address to, uint256 amount) external;

    function receiveFees(uint256 amount) external;
    function receivePrincipal(uint256 amount) external; // ← ADD
}

contract Bnpl is Ownable, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public DOMAIN_SEPARATOR;

    string public constant NAME = "BNPL";
    string public constant VERSION = "1";

    bytes32 public constant USER_ORDER_TYPEHASH =
        keccak256(
            "UserOrder(address user,uint256 tradeId,address baseAsset,uint256 assetAmount ,uint256 nusdAmount,uint256 maxPrice,uint256 nonce,uint8 side)"
        );

    bytes32 public constant EXECUTION_TYPEHASH =
        keccak256(
            "Execution(address user,uint256 tradeId,uint256 executionPrice,uint256 assetAmount,uint256 nusdAmount)"
        );

    bytes32 public constant WITHDRAW_TYPEHASH =
        keccak256(
            "Withdraw(address user,uint256 tradeId,uint256 amount,uint256 salt)"
        );

    bytes32 public constant LIQUIDATION_TYPEHASH =
        keccak256(
            "Liquidation(address user,uint256 tradeId,address baseAsset,uint256 price,uint256 assetAmount)"
        );

    bytes32 public constant LIQUIDATION_SETTLE_TYPEHASH =
        keccak256(
            "LiquidationSettle(address liquidator,uint256 tradeId,uint256 amount)"
        );

    IBnplSubscription public subscriptionContract;
    ITokenWhitelist public tokenWhitelist;
    IBnplVault public vaultContract;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    IERC20 public immutable NUSD =
        IERC20(0x5257bdd1F82de2b5906e83bdb87776DBA7DBDa97);

    // ------------ Fees -------------------
    uint256 public constant FEE_BASE = 10000;

    uint256 private tradeFee = 100; // 1000 = 1%
    uint256 private liquidateFee = 100;
    uint256 private deliveryFee = 1000; // 1000 = 10%
    uint256 private bufferPer = 10; //  0.1%

    // ----------------  Struct ------------------------

    struct UserDetails {
        uint256 totalTradeAmount;
        uint256 tradedAmount;
        uint256 lastUpdated;
    }

    struct TradeInfo {
        uint tradeId;
        uint multiplier;
        uint margin; // user amount
        uint borrowed; // leverage amount
        uint position; // total trade amount
        uint assetAmount; // purchase asset token
        uint tradeFee; // tradeFee initially
        // uint borrowFee;
        uint256 accumulatedBorrowFee; //  total fee till now
        uint64 lastFeeTimestamp; // last update time
        address baseAsset;
        uint entryPrice;
        uint liquidatePrice;
        uint64 openTimestamp;
        uint64 closeTimestamp;
        bool isTradeActive;
        bool isTradeLiquidate;
        bool isAssetDelivered;
        bool isExecutionWithdrawn;
    }

    struct DeliveryInfo {
        address baseAsset;
        uint assetAmount;
        uint deliveryFee;
        uint payBorrowAmount;
        uint totalBorrowFee;
        uint64 deliveryTimestamp;
    }

    struct LiquidateInfo {
        address baseAsset;
        uint256 assetAmount; // how much asset given to liquidator
        uint256 expectedDebt; // total NUSD to return (borrowed + fees)
        uint256 liquidationPenalty; // protocol fee
        uint256 totalBorrowFee; // accumulated borrow fee
        uint256 liquidateAssetPrice; // price at liquidation
        address liquidator; // who took the asset
        uint64 liquidateTimestamp; // start time
        uint64 settleDeadline; // deadline to return funds
        bool isSettled; // whether liquidation is completed
    }

    struct UserOrder {
        address user;
        address baseAsset;
        uint256 tradeId;
        uint256 assetAmount;
        uint256 nusdAmount;
        uint256 maxPrice;
        uint256 nonce;
        uint8 side; // 0 = BUY, 1 = SELL
    }

    struct Execution {
        uint256 executionPrice;
        uint256 assetAmount;
        uint256 nusdAmount;
    }

    struct BorrowRateSlab {
        uint256 maxUtilization; //  25, 50, 75, 100
        uint256 rate; // in basis points (100 = 1%)
    }

    // -------------------- Mapping -------------------------

    uint256 public totalBorrowed;
    BorrowRateSlab[] public borrowRateSlabs;

    mapping(address => bool) public isWhitelisted;

    mapping(address => UserDetails) public userDetails;
    mapping(uint256 => DeliveryInfo) public deliveryInfo;
    mapping(uint256 => LiquidateInfo) public liquidateInfo;

    mapping(uint256 => TradeInfo) public trades;
    mapping(uint256 => address) public tradeOwner;
    mapping(address => uint256[]) public userTradeIds;

    mapping(bytes32 => bool) public usedDigests;

    uint256 public nextTradeId = 1;

    // ---------- Events ----------------------

    event TradeOpened(
        address user,
        address baseAsset,
        uint tradeId,
        uint amount,
        uint multiplier,
        uint position
    );

    event TradeDelivered(
        address user,
        uint tradeId,
        address baseAsset,
        uint asssetAmount,
        uint deliveryFeeAmount,
        uint borrowFee,
        uint totalPayable
    );
    event TradeExecuted(
        address indexed user,
        uint256 indexed tradeId,
        address indexed baseAsset,
        uint8 side, // 0 = BUY, 1 = SELL
        uint256 executionPrice,
        uint256 assetAmount,
        uint256 nusdAmount,
        uint64 timestamp
    );
    event TradeLiquidated(
        address indexed user,
        uint256 indexed tradeId,
        address indexed liquidator,
        address baseAsset,
        uint256 assetAmount,
        uint256 liquidationPrice,
        uint256 liquidationPenalty,
        uint256 borrowFee,
        uint256 totalDebt,
        uint64 timestamp
    );

    event LiquidationSettled(
        address indexed liquidator,
        uint256 indexed tradeId,
        uint256 repaidAmount,
        uint256 expectedDebt,
        uint256 excessAmount,
        uint64 timestamp
    );

    event ForceClosedUnexecuted(
        address indexed user,
        uint256 indexed tradeId,
        uint256 totalDebt,
        uint256 recoveredAmount,
        uint256 badDebt,
        uint64 timestamp
    );

    event ExecutionWithdrawn(
        address indexed user,
        uint256 indexed tradeId,
        uint256 amount,
        bool isExecutionWithdrawn,
        uint64 timestamp
    );
    event VaultUpdated(address indexed oldVault, address indexed newVault);
    event FeesUpdated(
        uint256 tradeFee,
        uint256 liquidateFee,
        uint256 deliveryFee,
        uint256 bufferPer
    );

    constructor(
        address subscriptionAddr,
        address tokenWhitelistAddr,
        address vaultAddr,
        address _OPERATOR_ROLE,
        address _SIGNER_ROLE
    ) Ownable(msg.sender) {
        subscriptionContract = IBnplSubscription(subscriptionAddr);
        tokenWhitelist = ITokenWhitelist(tokenWhitelistAddr);
        vaultContract = IBnplVault(vaultAddr);

        _grantRole(OPERATOR_ROLE, _OPERATOR_ROLE);
        _grantRole(SIGNER_ROLE, _SIGNER_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                block.chainid,
                address(this)
            )
        );

        borrowRateSlabs.push(BorrowRateSlab(25, 100)); // 1%
        borrowRateSlabs.push(BorrowRateSlab(50, 150)); // 1.5%
        borrowRateSlabs.push(BorrowRateSlab(75, 200)); //2%
        borrowRateSlabs.push(BorrowRateSlab(100, 250)); // 2.5%
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    modifier onlyWhitelisted() {
        require(isWhitelisted[msg.sender], "NOT_WHITELISTED");
        _;
    }

    // --------------- Set Functions ------------------

    function setSubscriptionContract(
        address subscriptionAddr
    ) external onlyOwner {
        require(subscriptionAddr != address(0), "zero subscription address");
        subscriptionContract = IBnplSubscription(subscriptionAddr);
    }

    function setTokenContract(address whitelistAddr) external onlyOwner {
        require(whitelistAddr != address(0), "zero address");
        tokenWhitelist = ITokenWhitelist(whitelistAddr);
    }

    function setWhitelist(
        address[] calldata users,
        bool status
    ) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < users.length; i++) {
            isWhitelisted[users[i]] = status;
        }
    }

    function setBorrowRateSlabs(
        uint256[] calldata maxUtilizations,
        uint256[] calldata rates
    ) external onlyOwner {
        require(maxUtilizations.length == rates.length, "INVALID_LENGTH");
        require(maxUtilizations.length > 0, "EMPTY");

        delete borrowRateSlabs;

        uint256 prev = 0;

        for (uint256 i = 0; i < maxUtilizations.length; i++) {
            require(maxUtilizations[i] > prev, "NOT_SORTED");
            require(maxUtilizations[i] <= 100, "MAX_100");

            borrowRateSlabs.push(
                BorrowRateSlab({
                    maxUtilization: maxUtilizations[i],
                    rate: rates[i]
                })
            );

            prev = maxUtilizations[i];
        }

        require(
            maxUtilizations[maxUtilizations.length - 1] == 100,
            "MUST_END_100"
        );
    }

    function setOperator(address operator) external onlyOwner {
        require(operator != address(0), "zero address");
        _grantRole(OPERATOR_ROLE, operator);
    }

    function setVaultContract(address _vaultAddr) external onlyOwner {
        require(_vaultAddr != address(0), "zero address");
        vaultContract = IBnplVault(_vaultAddr);
        emit VaultUpdated(address(vaultContract), _vaultAddr);
    }

    function setFees(
        uint256 _tradeFee,
        uint256 _liquidateFee,
        uint256 _deliveryFee,
        uint256 _bufferPer
    ) external onlyOwner {
        // Max limits (adjust as needed)
        require(_tradeFee <= 500, "TRADE_FEE_TOO_HIGH"); // max 5%
        require(_liquidateFee <= 1000, "LIQUIDATE_FEE_TOO_HIGH"); // max 10%
        require(_deliveryFee <= 2000, "DELIVERY_FEE_TOO_HIGH"); // max 20%
        require(_bufferPer <= 100, "BUFFER_TOO_HIGH"); // max 1%

        tradeFee = _tradeFee;
        liquidateFee = _liquidateFee;
        deliveryFee = _deliveryFee;
        bufferPer = _bufferPer;

        emit FeesUpdated(_tradeFee, _liquidateFee, _deliveryFee, _bufferPer);
    }

    // --------------- Get Functions ------------------

    function getCurrentBorrowRate() public view returns (uint256) {
        uint256 available = IERC20(NUSD).balanceOf(address(vaultContract));

        uint256 totalLiquidity = available + totalBorrowed;

        if (totalLiquidity == 0) {
            return borrowRateSlabs[0].rate;
        }

        uint256 utilization = (totalBorrowed * 100) / totalLiquidity;

        for (uint256 i; i < borrowRateSlabs.length; i++) {
            if (utilization <= borrowRateSlabs[i].maxUtilization) {
                return borrowRateSlabs[i].rate;
            }
        }

        return borrowRateSlabs[borrowRateSlabs.length - 1].rate;
    }

    function getAllFee() external view returns (uint256, uint256, uint256) {
        return (tradeFee, liquidateFee, deliveryFee);
    }

    function _getDynamicBorrowRate() internal view returns (uint256) {
        uint256 vaultBalance = IERC20(NUSD).balanceOf(address(vaultContract));

        if (vaultBalance == 0)
            return borrowRateSlabs[borrowRateSlabs.length - 1].rate;

        uint256 utilization = (totalBorrowed * 100) / vaultBalance;

        for (uint256 i = 0; i < borrowRateSlabs.length; i++) {
            if (utilization <= borrowRateSlabs[i].maxUtilization) {
                return borrowRateSlabs[i].rate;
            }
        }

        // fallback (should never hit)
        return borrowRateSlabs[borrowRateSlabs.length - 1].rate;
    }

    function getUserTradeFee(
        uint amount,
        uint multiplier
    )
        public
        view
        returns (uint amountWithLeverage, uint tradeAmount, uint openFees)
    {
        amountWithLeverage = amount * multiplier;
        openFees = (amountWithLeverage * tradeFee) / FEE_BASE;
        tradeAmount = amountWithLeverage - openFees;
        return (amountWithLeverage, tradeAmount, openFees);
    }

    function getUserDeliveredIds(
        address user
    ) external view returns (uint256[] memory) {
        uint256[] memory ids = userTradeIds[user];
        uint256 len = ids.length;

        uint256[] memory temp = new uint256[](len);
        uint256 count = 0;

        for (uint256 i = 0; i < len; i++) {
            uint256 tradeId = ids[i];

            if (
                trades[tradeId].isAssetDelivered ||
                deliveryInfo[tradeId].deliveryTimestamp != 0
            ) {
                temp[count++] = tradeId;
            }
        }

        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    function isOperator(address account) external view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    // ------------  USER GET Functions ----------------------------

    function getUserTradeIds(
        address user
    ) external view returns (uint256[] memory) {
        return userTradeIds[user];
    }

    function getTrade(
        uint256 tradeId
    ) external view returns (TradeInfo memory) {
        require(tradeOwner[tradeId] != address(0), "GetTrade: Trade not found");
        return trades[tradeId];
    }

    function getUserTrades(
        address user,
        uint256 start,
        uint256 limit
    ) external view returns (TradeInfo[] memory) {
        uint256[] memory ids = userTradeIds[user];
        uint256 len = ids.length;

        if (start >= len) return new TradeInfo[](0);

        uint256 end = start + limit;
        if (end > len) end = len;

        TradeInfo[] memory result = new TradeInfo[](end - start);

        uint256 index = 0;
        for (uint256 i = start; i < end; i++) {
            result[index++] = trades[ids[i]];
        }

        return result;
    }

    function getUserDetails(
        address user
    ) external view returns (UserDetails memory) {
        return userDetails[user];
    }

    function getTradeOwner(uint256 tradeId) external view returns (address) {
        return tradeOwner[tradeId];
    }

    function getUserActiveTradeIds(
        address user
    ) external view returns (uint256[] memory) {
        uint256[] memory ids = userTradeIds[user];
        uint256 len = ids.length;

        uint256[] memory temp = new uint256[](len);
        uint256 count = 0;

        for (uint256 i = 0; i < len; i++) {
            TradeInfo memory t = trades[ids[i]];

            if (
                t.isTradeActive &&
                !t.isTradeLiquidate &&
                !t.isAssetDelivered &&
                t.entryPrice != 0
            ) {
                temp[count++] = ids[i];
            }
        }

        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    // -------------   Liquidate Details ---------------------------

    function getLiquidationPrice(
        uint256 tradeId
    ) public view returns (uint256) {
        require(tradeOwner[tradeId] != address(0), "TRADE_NOT_FOUND");

        TradeInfo memory t = trades[tradeId];
        require(t.isTradeActive, "TRADE_NOT_ACTIVE");

        return _getLiquidationPrice(t);
    }

    function previewLiquidationPrice(
        uint256 amount, // user margin
        uint256 multiplier, // leverage
        uint256 entryPrice // current market price
    ) external view returns (uint256) {
        require(amount > 0, "INVALID_AMOUNT");
        require(multiplier > 0, "INVALID_MULTIPLIER");
        require(entryPrice > 0, "INVALID_PRICE");

        uint256 amountWithLeverage = amount * multiplier;

        uint256 fee = (amountWithLeverage * tradeFee) / FEE_BASE;

        uint256 position = amountWithLeverage - fee;
        uint256 borrowed = amountWithLeverage - amount;

        uint256 liquidationPenalty = (position * liquidateFee) / FEE_BASE;

        uint256 buffer = (position * bufferPer) / FEE_BASE; // 0.1%

        uint256 totalDebt = borrowed + liquidationPenalty + buffer;

        return (totalDebt * entryPrice) / position;
    }

    function canLiquidate(
        uint256 tradeId,
        uint256 currentPrice
    ) public view returns (bool) {
        uint256 liqPrice = getLiquidationPrice(tradeId);
        return currentPrice <= liqPrice;
    }

    // ---------  Delivery Details -----------------

    function getDeliveryAmounts(
        uint256 tradeId
    )
        external
        view
        returns (
            uint256 deliveryFeeAmount,
            uint256 borrowFee,
            uint256 payBorrowAmount,
            uint256 totalAmountPay
        )
    {
        require(
            tradeOwner[tradeId] != address(0),
            "GetDeliveryAmounts: TRADE_NOT_FOUND"
        );

        TradeInfo memory t = trades[tradeId];
        require(t.isTradeActive, "GetDeliveryAmounts: TRADE_NOT_ACTIVE");

        (
            borrowFee,
            deliveryFeeAmount,
            payBorrowAmount,
            totalAmountPay
        ) = _getDeliveryAmounts(t);
    }

    function getDeliveryInfo(
        uint256 tradeId
    ) external view returns (DeliveryInfo memory) {
        require(
            tradeOwner[tradeId] != address(0),
            "GetDeliveryInfo: TRADE_NOT_FOUND"
        );
        DeliveryInfo memory d = deliveryInfo[tradeId];
        require(d.deliveryTimestamp != 0, "GetDeliveryInfo: DELIVERY_NOT_DONE");

        return d;
    }

    function getUserDeliveryInfo(
        uint256 tradeId
    ) external view returns (DeliveryInfo memory) {
        require(
            tradeOwner[tradeId] == msg.sender,
            "GetUserDeliveryInfo: NOT_OWNER"
        );
        DeliveryInfo memory d = deliveryInfo[tradeId];
        require(
            d.deliveryTimestamp != 0,
            "GetUserDeliveryInfo: DELIVERY_NOT_DONE"
        );
        return d;
    }

    function getUserDeliveries(
        address user
    ) external view returns (DeliveryInfo[] memory) {
        uint256[] memory ids = userTradeIds[user];
        uint256 len = ids.length;

        // max possible
        DeliveryInfo[] memory temp = new DeliveryInfo[](len);

        uint256 count = 0;

        for (uint256 i = 0; i < len; i++) {
            uint256 tradeId = ids[i];

            if (deliveryInfo[tradeId].deliveryTimestamp != 0) {
                temp[count++] = deliveryInfo[tradeId];
            }
        }

        // resize array
        DeliveryInfo[] memory result = new DeliveryInfo[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    function getUserLiquidatedTradeIds(
        address user
    ) external view returns (uint256[] memory) {
        uint256[] memory ids = userTradeIds[user];
        uint256 len = ids.length;

        uint256[] memory temp = new uint256[](len);
        uint256 count = 0;

        for (uint256 i = 0; i < len; i++) {
            uint256 tradeId = ids[i];

            if (
                (trades[tradeId].isTradeLiquidate &&
                    trades[tradeId].liquidatePrice > 0) ||
                liquidateInfo[tradeId].liquidateAssetPrice > 0
            ) {
                temp[count++] = tradeId;
            }
        }

        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    // ------------------ Internal FUnction --------------------

    function _validateSubscription(
        address user
    ) internal view returns (uint256 maxTrade, uint256 maxMultiplier) {
        IBnplSubscription.Subscription memory sub = subscriptionContract
            .subscriptions(user);
        require(sub.isSubscribe, "NOT_SUBSCRIBED");
        require(block.timestamp <= sub.expires, "SUBSCRIPTION_EXPIRED");

        maxMultiplier = sub.multiplier;
        maxTrade = sub.maxTradeAmount;
    }

    function _elapsedHours(uint64 fromTime) internal view returns (uint256) {
        if (block.timestamp <= fromTime) return 0;
        return (block.timestamp - fromTime) / 1 days;
    }

    function _calculateBorrowFee(
        uint256 amount,
        uint64 openTimestamp
    ) internal view returns (uint256 borrowFee) {
        uint256 daysElapsed = _elapsedHours(openTimestamp);

        if (daysElapsed == 0) return 0;

        uint256 rate = getCurrentBorrowRate();

        borrowFee = (amount * rate * daysElapsed) / FEE_BASE;
    }

    function _getLiquidationPrice(
        TradeInfo memory t
    ) internal view returns (uint256) {
        require(t.entryPrice > 0, "INVALID_ENTRY_PRICE");

        uint256 entryPrice = t.entryPrice;
        uint256 position = t.position;
        uint256 borrowed = t.borrowed;

        uint256 borrowFee = _calculateBorrowFee(borrowed, t.openTimestamp);

        uint256 liquidationPenalty = (position * liquidateFee) / FEE_BASE;
        uint256 buffer = (position * bufferPer) / FEE_BASE; // 0.1%

        uint256 totalDebt = borrowed + borrowFee + liquidationPenalty + buffer;

        return (totalDebt * entryPrice) / position;
    }

    function _getDeliveryAmounts(
        TradeInfo memory t
    )
        internal
        view
        returns (
            uint256 borrowFee,
            uint256 deliveryFeeAmount,
            uint256 payBorrowAmount,
            uint256 totalAmountPay
        )
    {
        borrowFee = _calculateBorrowFee(t.borrowed, t.openTimestamp);
        deliveryFeeAmount = (t.position * deliveryFee) / FEE_BASE;
        payBorrowAmount = t.borrowed;
        // total payment
        totalAmountPay = payBorrowAmount + borrowFee + deliveryFeeAmount;
    }

    function getUserDepositTradeIds(
        address user
    ) external view returns (uint256[] memory) {
        uint256[] memory ids = userTradeIds[user];
        uint256 len = ids.length;

        uint256[] memory temp = new uint256[](len);
        uint256 count = 0;

        for (uint256 i = 0; i < len; i++) {
            TradeInfo memory t = trades[ids[i]];

            if (
                t.isTradeActive &&
                !t.isTradeLiquidate &&
                !t.isAssetDelivered &&
                t.entryPrice == 0
            ) {
                temp[count++] = ids[i];
            }
        }

        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    // ------------------ Function ----------------------

    function getBorrowFee(uint256 tradeId) public view returns (uint256) {
        TradeInfo memory t = trades[tradeId];

        require(tradeOwner[tradeId] != address(0), "TRADE_NOT_FOUND");
        require(t.isTradeActive, "TRADE_NOT_ACTIVE");

        return _calculateBorrowFee(t.borrowed, t.openTimestamp);
    }

    function deposit(
        address baseAsset,
        uint amount,
        uint multiplier
    )
        public
        onlyWhitelisted
        whenNotPaused
        returns (uint256 tradeId, uint borrowed)
    {
        require(amount > 0, "Deposite: invalid amount");
        UserDetails storage u = userDetails[msg.sender];
        (uint256 maxTrade, uint256 maxMultiplier) = _validateSubscription(
            msg.sender
        );

        tradeId = nextTradeId++;
        require(multiplier <= maxMultiplier, "Deposite: invalid multiplier");

        // -------- Token Whitelist Check --------
        tokenWhitelist.validateTradeToken(baseAsset);

        (uint amountWithLeverage, uint position, uint fee) = getUserTradeFee(
            amount,
            multiplier
        );
        require(position > amount, " Deposite: invalid position");

        uint256 newExposure = u.tradedAmount + position;

        require(
            newExposure <= maxTrade,
            "Deposite: EXCEEDS_USER_LIMIT for trade"
        );

        IERC20(NUSD).safeTransferFrom(msg.sender, address(this), amount);

        if (fee > 0) {
            IERC20(NUSD).approve(address(vaultContract), fee);
            vaultContract.receiveFees(fee);
        }

        borrowed = amountWithLeverage - amount;

        // -------- Vault Safety --------
        uint vaultBal = IERC20(NUSD).balanceOf(address(vaultContract));
        require(
            vaultBal >= borrowed,
            "Deposite: insufficient liquidity in Vault"
        );

        // -------- Borrow --------
        if (borrowed != 0) {
            vaultContract.transferToken(
                address(IERC20(NUSD)),
                address(this),
                borrowed
            );
            totalBorrowed += borrowed;
        }

        TradeInfo storage t = trades[tradeId];

        t.tradeId = tradeId;
        t.multiplier = multiplier;
        t.margin = amount - fee;
        t.borrowed = borrowed;
        t.position = position;
        t.baseAsset = baseAsset;
        t.tradeFee = fee;
        t.openTimestamp = uint64(block.timestamp);
        t.isTradeActive = true;

        u.tradedAmount += position;
        u.totalTradeAmount += position;
        u.lastUpdated = block.timestamp;

        // -------- LINK --------
        tradeOwner[tradeId] = msg.sender;
        userTradeIds[msg.sender].push(tradeId);

        // -------- EVENT --------
        emit TradeOpened(
            msg.sender,
            baseAsset,
            tradeId,
            amount,
            multiplier,
            position
        );

        return (tradeId, borrowed);
    }

    function deliverTrade(uint256 tradeId) external nonReentrant whenNotPaused {
        require(tradeOwner[tradeId] == msg.sender, "NOT_OWNER");

        TradeInfo storage t = trades[tradeId];

        require(t.isTradeActive, "DeliverTrade : TRADE_NOT_ACTIVE");
        require(!t.isTradeLiquidate, "DeliverTrade: TRADE_LIQUIDATED");
        require(!t.isAssetDelivered, "DeliverTrade: ALREADY_DELIVERED");
        // require(t.isExecuted, "TRADE_NOT_EXECUTED");

        // uint256 borrowFee = _calculateBorrowFee(t.borrowed, t.openTimestamp);
        // uint256 deliveryFeeAmount = (t.position * deliveryFee) / FEE_BASE;

        // uint256 totalPayable = t.borrowed + borrowFee + deliveryFeeAmount;

        (
            uint256 borrowFee,
            uint256 deliveryFeeAmount,
            ,
            uint256 totalPayable
        ) = _getDeliveryAmounts(t);

        if (totalPayable > 0) {
            IERC20(NUSD).safeTransferFrom(
                msg.sender,
                address(this),
                totalPayable
            );
        }

        // send fees to vault
        if (borrowFee + deliveryFeeAmount > 0) {
            IERC20(NUSD).approve(
                address(vaultContract),
                borrowFee + deliveryFeeAmount
            );
            vaultContract.receiveFees(borrowFee + deliveryFeeAmount);
        }

        // -------- Return borrowed to vault --------
        if (t.borrowed > 0) {
            // IERC20(NUSD).approve(address(vaultContract), t.borrowed);
            // vaultContract.transferToken(address(NUSD), address(vaultContract), t.borrowed);
            vaultContract.receivePrincipal(t.borrowed);
            totalBorrowed -= t.borrowed;
        }

        // -------- Deliver Asset --------

        require(
            IERC20(t.baseAsset).balanceOf(address(this)) >= t.assetAmount,
            "DeliverTrade: INSUFFICIENT_ASSET"
        );

        IERC20(t.baseAsset).safeTransfer(msg.sender, t.assetAmount);

        deliveryInfo[tradeId] = DeliveryInfo({
            baseAsset: t.baseAsset,
            assetAmount: t.assetAmount,
            deliveryFee: deliveryFeeAmount,
            payBorrowAmount: t.borrowed,
            totalBorrowFee: borrowFee,
            deliveryTimestamp: uint64(block.timestamp)
        });

        // -------- Update State --------

        t.isTradeActive = false;
        t.isAssetDelivered = true;
        t.closeTimestamp = uint64(block.timestamp);

        UserDetails storage u = userDetails[msg.sender];
        u.tradedAmount -= t.position;

        emit TradeDelivered(
            msg.sender,
            tradeId,
            t.baseAsset,
            t.assetAmount,
            deliveryFeeAmount,
            borrowFee,
            totalPayable
        );
    }

    function getTotalBorrowed() external view returns (uint256) {
    return totalBorrowed; // yeh already NET hai (bahar wala sirf)
}

    function executeTrade(
        UserOrder calldata order,
        Execution calldata exec,
        bytes calldata signerSig
    ) external nonReentrant whenNotPaused onlyWhitelisted {
        require(order.user == msg.sender, "ExecuteTrade: ONLY_USER");
        require(
            tradeOwner[order.tradeId] == order.user,
            "ExecuteTrade: NOT_OWNER"
        );

        TradeInfo storage t = trades[order.tradeId];

        require(t.isTradeActive, "ExecuteTrade: NOT_ACTIVE");
        require(!t.isTradeLiquidate, "ExecuteTrade: LIQUIDATED");
        require(t.entryPrice == 0, "ExecuteTrade: ALREADY_EXECUTED");
        require(t.isExecutionWithdrawn, "ExecuteTrade: NOT_WITHDRAWN");
        require(order.baseAsset == t.baseAsset, "BASE_ASSET_MISMATCH");

        // -------- SIGNER VALIDATION --------
        bytes32 digest = _hashExecution(order.user, order.tradeId, exec);

        require(!usedDigests[digest], "ExecuteTrade: EXEC_REPLAY");

        address signer = _recover(digest, signerSig);
        require(hasRole(SIGNER_ROLE, signer), "ExecuteTrade: BAD_SIGNER");

        usedDigests[digest] = true;

        // -------- VALIDATION --------
        require(exec.assetAmount > 0, "INVALID_ASSET");
        require(exec.assetAmount == order.assetAmount, "AMOUNT_MISMATCH");

        if (order.side == 0) {
            require(exec.executionPrice <= order.maxPrice, "PRICE_TOO_HIGH");
        } else {
            require(exec.executionPrice >= order.maxPrice, "PRICE_TOO_LOW");
        }

        require(exec.nusdAmount <= order.nusdAmount, "NUSD_EXCEEDS");

        IERC20 baseToken = IERC20(order.baseAsset);

        // enforce transfer from user → contract
        baseToken.safeTransferFrom(msg.sender, address(this), exec.assetAmount);

        // -------- EXECUTION STATE --------
        t.entryPrice = exec.executionPrice;
        t.assetAmount = exec.assetAmount;

        emit TradeExecuted(
            order.user,
            order.tradeId,
            order.baseAsset,
            order.side,
            exec.executionPrice,
            exec.assetAmount,
            exec.nusdAmount,
            uint64(block.timestamp)
        );
    }

    function withdrawForExecution(
        uint256 tradeId,
        uint256 salt,
        bytes calldata signerSig
    ) external nonReentrant onlyWhitelisted {
        require(tradeOwner[tradeId] == msg.sender, "Withdraw: NOT_OWNER");

        TradeInfo storage t = trades[tradeId];

        require(t.isTradeActive, "Withdraw: NOT_ACTIVE");
        require(t.entryPrice == 0, "Withdraw: ALREADY_EXECUTED");
        require(!t.isExecutionWithdrawn, "Withdraw: ALREADY_WITHDRAWN");

        uint256 amount = t.position;

        // ---------- HASH ----------
        bytes32 structHash = keccak256(
            abi.encode(WITHDRAW_TYPEHASH, msg.sender, tradeId, amount, salt)
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        require(!usedDigests[digest], "Withdraw: REPLAY");

        address signer = _recover(digest, signerSig);
        require(hasRole(SIGNER_ROLE, signer), "Withdraw: BAD_SIGNER");

        usedDigests[digest] = true;

        t.isExecutionWithdrawn = true;

        IERC20(NUSD).safeTransfer(msg.sender, amount);

        emit ExecutionWithdrawn(
            msg.sender,
            tradeId,
            amount,
            t.isExecutionWithdrawn,
            uint64(block.timestamp)
        );
    }

    // -----------------  Liquidate Logics -------------------------------------------

    function liquidateTrade(
        uint256 tradeId,
        uint256 currentPrice,
        bytes calldata signerSig
    ) external nonReentrant onlyWhitelisted {
        TradeInfo storage t = trades[tradeId];

        require(
            liquidateInfo[tradeId].liquidator == address(0),
            "LIQ_ALREADY_STARTED"
        );

        require(tradeOwner[tradeId] != address(0), "TRADE_NOT_FOUND");
        require(t.isTradeActive, "NOT_ACTIVE");
        require(!t.isTradeLiquidate, "ALREADY_LIQUIDATED");
        require(t.entryPrice > 0, "NOT_EXECUTED");
        require(t.assetAmount > 0, "NO_ASSET");
        require(
            IERC20(t.baseAsset).balanceOf(address(this)) >= t.assetAmount,
            "INSUFFICIENT_ASSET"
        );

        // -------- SIGNATURE VALIDATION --------
        bytes32 digest = _hashLiquidation(
            tradeOwner[tradeId],
            tradeId,
            t.baseAsset,
            currentPrice,
            t.assetAmount
        );

        require(!usedDigests[digest], "REPLAY");

        address signer = _recover(digest, signerSig);
        require(hasRole(SIGNER_ROLE, signer), "BAD_SIGNER");

        usedDigests[digest] = true;

        uint256 liqPrice = _getLiquidationPrice(t);
        require(currentPrice <= liqPrice, "NOT_LIQUIDATABLE");

        // -------- CALCULATIONS --------
        uint256 borrowFee = _calculateBorrowFee(t.borrowed, t.openTimestamp);
        uint256 penalty = (t.position * liquidateFee) / FEE_BASE;

        uint256 totalDebt = t.borrowed + borrowFee + penalty;

        // -------- STORE --------
        liquidateInfo[tradeId] = LiquidateInfo({
            baseAsset: t.baseAsset,
            assetAmount: t.assetAmount,
            expectedDebt: totalDebt,
            liquidationPenalty: penalty,
            totalBorrowFee: borrowFee,
            liquidateAssetPrice: currentPrice,
            liquidator: msg.sender,
            liquidateTimestamp: uint64(block.timestamp),
            settleDeadline: uint64(block.timestamp + 15 minutes),
            isSettled: false
        });

        // -------- STATE --------
        t.isTradeActive = false;
        t.isTradeLiquidate = true;
        t.liquidatePrice = currentPrice;

        // -------- TRANSFER ASSET --------

        IERC20(t.baseAsset).safeTransfer(msg.sender, t.assetAmount);

        emit TradeLiquidated(
            tradeOwner[tradeId],
            tradeId,
            msg.sender,
            t.baseAsset,
            t.assetAmount,
            currentPrice,
            penalty,
            borrowFee,
            totalDebt,
            uint64(block.timestamp)
        );
    }

    function settleLiquidation(
        uint256 tradeId,
        uint256 amount,
        bytes calldata signerSig
    ) external nonReentrant onlyWhitelisted {
        LiquidateInfo storage l = liquidateInfo[tradeId];
        TradeInfo storage t = trades[tradeId];

        require(tradeOwner[tradeId] != address(0), "TRADE_NOT_FOUND");
        require(msg.sender == l.liquidator, "NOT_LIQUIDATOR");
        require(!l.isSettled, "ALREADY_SETTLED");

        //  require(block.timestamp <= l.settleDeadline, "EXPIRED");

        // -------- SIGNATURE VALIDATION --------
        bytes32 digest = _hashLiquidationSettle(msg.sender, tradeId, amount);

        require(!usedDigests[digest], "REPLAY");

        address signer = _recover(digest, signerSig);
        require(hasRole(SIGNER_ROLE, signer), "BAD_SIGNER");

        usedDigests[digest] = true;

        // -------- TRANSFER NUSD --------
        IERC20(NUSD).safeTransferFrom(msg.sender, address(this), amount);

        require(amount >= l.expectedDebt, "INSUFFICIENT_REPAY");

        // -------- SEND TO VAULT --------

        uint256 repayAmount = l.expectedDebt;

        IERC20(NUSD).approve(address(vaultContract), repayAmount);
        vaultContract.receiveFees(repayAmount);

        // -------- FINALIZE --------
        l.isSettled = true;

        totalBorrowed -= t.borrowed;
        t.closeTimestamp = uint64(block.timestamp);

        UserDetails storage u = userDetails[tradeOwner[tradeId]];
        if (u.tradedAmount >= t.position) {
            u.tradedAmount -= t.position;
        }

        uint256 excess = 0;
        if (amount > l.expectedDebt) {
            excess = amount - l.expectedDebt;
            IERC20(NUSD).safeTransfer(msg.sender, excess);
        }

        emit LiquidationSettled(
            msg.sender,
            tradeId,
            amount,
            l.expectedDebt,
            excess,
            uint64(block.timestamp)
        );
    }

    // ------------------- Hash builders --------------------------------

    function _hashUserOrder(
        UserOrder calldata order
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                USER_ORDER_TYPEHASH,
                order.user,
                order.tradeId,
                order.baseAsset,
                order.assetAmount,
                order.nusdAmount,
                order.maxPrice,
                order.nonce,
                order.side
            )
        );

        return
            keccak256(
                abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
            );
    }

    function _hashExecution(
        address user,
        uint256 tradeId,
        Execution calldata exec
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                EXECUTION_TYPEHASH,
                user,
                tradeId,
                exec.executionPrice,
                exec.assetAmount,
                exec.nusdAmount
            )
        );

        return
            keccak256(
                abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
            );
    }

    // --------------------  Recovery Function ------------------------

    function _recover(
        bytes32 digest,
        bytes memory sig
    ) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        require(sig.length == 65, "INVALID_SIG");

        assembly ("memory-safe") {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        return ecrecover(digest, v, r, s);
    }

    function _validateUserSig(
        UserOrder calldata order,
        bytes calldata userSig
    ) internal returns (bytes32) {
        bytes32 digest = _hashUserOrder(order);

        require(!usedDigests[digest], "USER_REPLAY");

        address signer = _recover(digest, userSig);
        require(signer == order.user, "BAD_USER_SIG");

        usedDigests[digest] = true;

        return digest;
    }

    function _validateOperatorSig(
        address user,
        uint256 tradeId,
        Execution calldata exec,
        bytes calldata operatorSig
    ) internal returns (bytes32) {
        bytes32 digest = _hashExecution(user, tradeId, exec);

        require(!usedDigests[digest], "EXEC_REPLAY");

        address signer = _recover(digest, operatorSig);
        require(hasRole(OPERATOR_ROLE, signer), "BAD_OPERATOR");

        usedDigests[digest] = true;

        return digest;
    }

    function _hashLiquidation(
        address user,
        uint256 tradeId,
        address baseAsset,
        uint256 price,
        uint256 assetAmount
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                LIQUIDATION_TYPEHASH,
                user,
                tradeId,
                baseAsset,
                price,
                assetAmount
            )
        );

        return
            keccak256(
                abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
            );
    }

    function _hashLiquidationSettle(
        address liquidator,
        uint256 tradeId,
        uint256 amount
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(LIQUIDATION_SETTLE_TYPEHASH, liquidator, tradeId, amount)
        );

        return
            keccak256(
                abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
            );
    }

    //. ---------------------   Emergency Functions ----------------------

    function forceCloseUnexecuted(
        uint256 tradeId
    ) external onlyOwner nonReentrant {
        require(tradeOwner[tradeId] != address(0), "TRADE_NOT_FOUND");

        TradeInfo storage t = trades[tradeId];
        address user = tradeOwner[tradeId];

        require(t.isExecutionWithdrawn, "NOT_WITHDRAWN");
        require(t.entryPrice == 0, "ALREADY_EXECUTED");
        require(t.isTradeActive, "NOT_ACTIVE");

        // -------- CALCULATE DEBT --------
        uint256 borrowFee = _calculateBorrowFee(t.borrowed, t.openTimestamp);

        uint256 totalDebt = t.borrowed + borrowFee;

        // -------- TRY TO RECOVER FUNDS --------
        uint256 userBal = IERC20(NUSD).balanceOf(user);

        uint256 recoverAmount = userBal >= totalDebt ? totalDebt : userBal;

        if (recoverAmount > 0) {
            require(
                IERC20(NUSD).allowance(user, address(this)) >= recoverAmount,
                "ALLOWANCE_MISSING"
            );
            IERC20(NUSD).safeTransferFrom(user, address(this), recoverAmount);

            // send recovered to vault
            IERC20(NUSD).approve(address(vaultContract), recoverAmount);
            vaultContract.receiveFees(recoverAmount);
        }

        // -------- HANDLE BAD DEBT --------
        uint256 badDebt = 0;
        if (recoverAmount < totalDebt) {
            badDebt = totalDebt - recoverAmount;
        }

        // -------- UPDATE STATE --------
        t.isTradeActive = false;
        t.closeTimestamp = uint64(block.timestamp);

        totalBorrowed -= t.borrowed;

        // update user exposure
        UserDetails storage u = userDetails[user];
        if (u.tradedAmount >= t.position) {
            u.tradedAmount -= t.position;
        }

        // -------- EVENT --------
        emit ForceClosedUnexecuted(
            user,
            tradeId,
            totalDebt,
            recoverAmount,
            badDebt,
            uint64(block.timestamp)
        );
    }
}
