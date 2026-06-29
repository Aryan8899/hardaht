// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IFundProvider {
    function requestFunds(address token, uint256 amount) external;
}
interface IMMVaultFactory {
    function whitelisted(address) external view returns (bool);
}

contract aryu is ReentrancyGuard ,Pausable{
    using SafeERC20 for IERC20;

    address public factory;

    address public token0;
    address public token1;
    // Staking config
    uint256 public constant APY = 1000; // 10%
    uint256 public constant CLAIM_INTERVAL = 5 minutes;
    uint256 public minStakeAmount; // set in initialize()

    // Totals
    uint256 public totalStakeAmount;
    uint256 public totalStakeClaimAmount;
    uint256 public totalRewardClaim;
    uint256 public totalUniqueAddress;

    bool public initialized;

    // -- MAPPING
    mapping(address => bool) public operators;
    mapping(address => UserInfo) public userInfo;

    // ----- STRUCT  -----

    struct UserInfo {
        uint256 amount;
        uint256 rewardStored;
        uint256 rewardClaimed;
        uint256 lastUpdateTime;
        uint256 lastClaimTime;
        uint256 amountclaimed;
    }

    // -------- EVENTS --------

    event Initialized(address token0, address token1);
    event Deposited(
        address indexed from,
        address indexed token,
        uint256 amount
    );
    event Withdrawn(
        address indexed operator,
        address indexed to,
        address indexed token,
        uint256 amount
    );
    event Executed(address indexed operator, address target);
    event FundsRequested(
        address indexed operator,
        address provider,
        address token,
        uint256 amount
    );
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    // -------- MODIFIERS --------

    modifier onlyFactory() {
        require(msg.sender == factory, "Not factory");
        _;
    }

  modifier onlyOperator() {
    require(IMMVaultFactory(factory).whitelisted(msg.sender), "Not whitelisted");
    _;
}

  constructor(uint256 _minStakeAmount) {
    factory = msg.sender;
    minStakeAmount = _minStakeAmount;  // ✅ yahan set
}

    // -------- INITIALIZE --------

    function initialize(
        address _token0,
        address _token1,
        
        address[] calldata _operators
    ) external onlyFactory {
        require(!initialized, "Already initialized");
        require(_token0 != _token1, "Identical tokens");
        require(_operators.length > 0, "No operators");

        token0 = _token0;
        token1 = _token1;

        for (uint256 i = 0; i < _operators.length; i++) {
            require(_operators[i] != address(0), "Zero operator");
            operators[_operators[i]] = true;
        }

        
        initialized = true;

        emit Initialized(_token0, _token1);
    }

    // -------- CORE --------

    function deposit(address token, uint256 amount) external nonReentrant {
        require(token == token0 || token == token1, "Invalid token");
        require(amount > 0, "Amount=0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, token, amount);
    }

    function operatorWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOperator nonReentrant {
        require(token == token0 || token == token1, "Invalid token");

        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(msg.sender, to, token, amount);
    }

    // -------- VIEW --------

    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

      // ======================================================
    //                   STAKING LOGIC
    // ======================================================

    /// @dev Internal: reward calculate karke store karo
    function _updateReward(address _user) internal {
        UserInfo storage user = userInfo[_user];

        if (user.amount > 0) {
            uint256 timeElapsed = block.timestamp - user.lastUpdateTime;
            uint256 reward = calculateReward(user.amount, timeElapsed);
            user.rewardStored += reward;
        }

        user.lastUpdateTime = block.timestamp;
    }

    /// @notice User tokens stake kare
    function stake(uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0 && _amount >= minStakeAmount, "Below min stake");

        UserInfo storage user = userInfo[msg.sender];

        // Pehli baar stake kar raha hai
        if (user.lastUpdateTime == 0) {
            totalUniqueAddress += 1;
        }

        _updateReward(msg.sender);

        IERC20(token0).safeTransferFrom(msg.sender, address(this), _amount);


        user.amount += _amount;
        totalStakeAmount += _amount;

        emit Staked(msg.sender, _amount);
    }

    /// @notice User apna staked amount wapas le
   function unStake(uint256 _amount) external nonReentrant whenNotPaused {
    UserInfo storage user = userInfo[msg.sender];
    require(_amount > 0, "Invalid amount");

    _updateReward(msg.sender);

    uint256 principalAmount = user.amount;
    uint256 pendingRewards = user.rewardStored;
    uint256 totalAvailable = principalAmount + pendingRewards;

    require(principalAmount > 0, "Nothing staked");
    require(totalAvailable >= _amount, "Insufficient balance");
    require(
        block.timestamp >= user.lastClaimTime + CLAIM_INTERVAL,
        "Claim interval not passed"
    );

    // CASE 1: Full unstake
    if (_amount == totalAvailable) {
        user.amount = 0;
        user.rewardStored = 0;
        user.rewardClaimed += pendingRewards;
        user.amountclaimed += principalAmount;
        user.lastClaimTime = block.timestamp;

        totalStakeAmount -= principalAmount;
        totalStakeClaimAmount += principalAmount;
        totalRewardClaim += pendingRewards;

        require(IERC20(token0).balanceOf(address(this)) >= _amount, "Insufficient balance");
        IERC20(token0).safeTransfer(msg.sender, _amount);
        emit Unstaked(msg.sender, principalAmount);
        emit RewardClaimed(msg.sender, pendingRewards);
        return;
    }

    // CASE 2 & 3: Partial
    uint256 remainingUnstake = _amount;

    if (pendingRewards > 0) {
        if (pendingRewards >= _amount) {
            // CASE 2: sirf reward se cover
            user.rewardStored = pendingRewards - _amount;
            user.rewardClaimed += _amount;
            user.lastClaimTime = block.timestamp;
            totalRewardClaim += _amount;

            require(IERC20(token0).balanceOf(address(this)) >= _amount, "Insufficient balance");
            IERC20(token0).safeTransfer(msg.sender, _amount);
            emit RewardClaimed(msg.sender, _amount);
            remainingUnstake = 0;

        } else {
            // CASE 3: pehle reward phir principal
            uint256 fromPrincipal = _amount - pendingRewards;

            user.rewardStored = 0;
            user.rewardClaimed += pendingRewards;
            user.lastClaimTime = block.timestamp;
            totalRewardClaim += pendingRewards;

            require(IERC20(token0).balanceOf(address(this)) >= pendingRewards, "Insufficient balance");
            IERC20(token0).safeTransfer(msg.sender, pendingRewards);
            emit RewardClaimed(msg.sender, pendingRewards);
            remainingUnstake = fromPrincipal;
        }
    }

    if (remainingUnstake > 0) {
        require(user.amount >= remainingUnstake, "Insufficient staked balance");

        user.amount -= remainingUnstake;
        user.amountclaimed += remainingUnstake;
        totalStakeAmount -= remainingUnstake;
        totalStakeClaimAmount += remainingUnstake;

        require(IERC20(token0).balanceOf(address(this)) >= remainingUnstake, "Insufficient balance");
        IERC20(token0).safeTransfer(msg.sender, remainingUnstake);
        emit Unstaked(msg.sender, remainingUnstake);
    }
}

    /// @notice User apna reward claim kare
  

    // ======================================================
    //                   VIEW FUNCTIONS
    // ======================================================

    /// @notice Pending reward dekho kisi bhi user ka
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo memory user = userInfo[_user];

        if (user.amount == 0) return 0;

        uint256 timeElapsed = block.timestamp - user.lastUpdateTime;
        uint256 newReward = calculateReward(user.amount, timeElapsed);

        return user.rewardStored + newReward;
    }

    /// @notice APY ke hisaab se reward calculate karo
    function calculateReward(uint256 _amount, uint256 _time) public pure returns (uint256) {
        return (_amount * APY * _time) / (365 days * 10000);
    }



}

