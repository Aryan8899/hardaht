// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IPoclContract {
    function collectBorrowFee(uint256 amount) external;
}

contract BnplVault is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // NUSC token
    IERC20 public immutable token =
        IERC20(0x14E35846856654693161d68Ea92caC952FF1b6f5);

    uint256 public constant BPS = 10_000;
    uint256 public constant YEAR = 365 days;
    uint256 private constant MIN_PROFIT_PERIOD = 1 days;
    uint256 private constant ACC_PRECISION = 1e18;

    uint256 public STAKER_SHARE_BPS = 7_000;
    uint256 public POCL_SHARE_BPS = 3_000;

    uint256 public constant MIN_APY_BPS = 300;
    uint256 public constant MAX_APY_BPS = 1_000;

    uint256 public constant RESERVE_SHARE_BPS = 1_800;
    uint256 public constant TREASURY_SHARE_BPS = 1_200;

    uint256 public maxBNPLUtilizationBps = 7_000;

    // ---------------- Addresses ----------------
    address public pocl;
    address public bnpl;
    address public reserve;
    address public treasury;

    // ---------------- Lending accounting ----------------
    uint256 public totalReceivedFromPOCL;
    uint256 public totalWithdrawnByPOCL;

    uint256 public totalBorrowed; // trasnfered to BNPL
    uint256 public totalRepaid; // Received from BNPL

    // ---------------- Staking ----------------
    bool public stakingEnabled;
    uint256 public totalStaked;
    uint256 public totalStakeClaimAmount;
    uint256 public totalRewardClaim;

    // ---------------- Profit ----------------
    uint256 public totalProfit;
    uint256 public lastProfitPeriod;

    // ---------------- Rewards ----------------
    uint256 public rewardPerTokenStored;
    uint256 public totalRewardsLiability;
    uint256 public lastStakerShare;

    uint256 public totalStakerRewardsDistributed;
    uint256 public lastProfitTime;

    struct UserInfo {
        uint256 amount;
        uint256 rewardStored;
        uint256 rewardClaimed;
        uint256 amountClaimed;
        uint256 lastClaimTime;
        uint256 totalRewardEarned;
        uint256 rewardPerTokenPaid;
        uint256 lastUpdateTime;
    }

    mapping(address => UserInfo) public users;

    // ---------------- Events ----------------
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 principal, uint256 reward);
    event RewardClaimed(address indexed user, uint256 amount);
    event ProfitReceived(
        address indexed source,
        uint256 totalProfit,
        uint256 stakerShare,
        uint256 reserveShare,
        uint256 treasuryShare
    );
    event FundsReceivedFromPOCL(uint256 amount);
    event FundsSentToBNPL(uint256 amount);
    event PrincipalReceived(uint256 amount);
    event StakingEnabledUpdated(bool enabled);
    event POCLUpdated(address indexed pocl);
    event BNPLUpdated(address indexed bnpl);
    event ReserveUpdated(address indexed reserve);
    event TreasuryUpdated(address indexed treasury);
    event FundsWithdrawnByPOCL(address indexed pocl, uint256 amount);
    error InvalidPOCLAccounting();
    error InvalidFeeShares();

    event NUSCStakedNotified(address indexed pocl, uint256 amount);
    event BorrowFeeSentToPOCL(address indexed pocl, uint256 amount);
    event BorrowFeeReceived(
        uint indexed borrowFee,
        uint indexed stakerReward,
        uint poclShare
    );

    event BNPLUtilizationLimitUpdated(uint256 oldLimitBps, uint256 newLimitBps);

    // ---------------- Errors ----------------
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientStake();
    error NoStakers();
    error NoReward();
    error InsufficientFunding();
    error InvalidRewardAmount();
    error StakingDisabled();
    error Unauthorized();
    error InvalidUtilizationLimit();
    error BNPLUtilizationLimitReached();

    modifier onlyBNPL() {
        if (msg.sender != bnpl) revert Unauthorized();
        _;
    }

    modifier onlyPOCL() {
        if (msg.sender != pocl) revert Unauthorized();
        _;
    }

    modifier updateReward(address account) {
        _updateUserReward(account);
        _;
    }

    constructor(address _pocl, address _bnpl) Ownable(msg.sender) {
        if (_pocl == address(0) || _bnpl == address(0)) revert ZeroAddress();

        pocl = _pocl;
        bnpl = _bnpl;
    }

    // --------------------------------------------------
    // STAKING
    // --------------------------------------------------

    function stake(
        uint256 amount
    ) external whenNotPaused nonReentrant updateReward(msg.sender) {
        if (!stakingEnabled) revert StakingDisabled();
        if (amount == 0) revert ZeroAmount();

        users[msg.sender].amount += amount;
        totalStaked += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function unstake(
        uint256 amount
    ) external whenNotPaused nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        UserInfo storage user = users[msg.sender];

        uint256 principal = user.amount;
        uint256 pending = user.rewardStored;

        if (principal == 0) revert InsufficientStake();
        if (amount > principal + pending) revert InsufficientStake();

        uint256 fromReward = amount < pending ? amount : pending;
        uint256 fromPrincipal = amount - fromReward;

        if (fromReward > 0) {
            user.rewardStored = pending - fromReward;
            user.rewardClaimed += fromReward;
            user.lastClaimTime = block.timestamp;
            totalRewardClaim += fromReward;
            totalRewardsLiability -= fromReward;
        }

        if (fromPrincipal > 0) {
            user.amount = principal - fromPrincipal;
            user.amountClaimed += fromPrincipal;
            totalStaked -= fromPrincipal;
            totalStakeClaimAmount += fromPrincipal;
        }

        token.safeTransfer(msg.sender, amount);

        if (fromReward > 0) emit RewardClaimed(msg.sender, fromReward);
        emit Unstaked(msg.sender, fromPrincipal, fromReward);
    }

    function claimReward()
        external
        whenNotPaused
        nonReentrant
        updateReward(msg.sender)
    {
        UserInfo storage user = users[msg.sender];

        uint256 reward = user.rewardStored;
        if (reward == 0) revert NoReward();

        user.rewardStored = 0;
        user.rewardClaimed += reward;
        user.lastClaimTime = block.timestamp;
        totalRewardClaim += reward;
        totalRewardsLiability -= reward;

        token.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    function transferToken(
        address _token,
        address to,
        uint256 amount
    ) external onlyBNPL nonReentrant whenNotPaused {
        if (_token != address(token)) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        if (amount > availableForBNPL()) {
            revert InsufficientFunding();
        }

        totalBorrowed += amount;

        token.safeTransfer(to, amount);

        emit FundsSentToBNPL(amount);
    }

    function receivePrincipal(
        uint256 amount
    ) external onlyBNPL nonReentrant whenNotPaused {
        token.safeTransferFrom(msg.sender, address(this), amount);

        totalRepaid += amount;

        emit PrincipalReceived(amount);
    }

    function notifyNUSCStaked(uint256 amount) external onlyPOCL nonReentrant {
        if (amount == 0) revert ZeroAmount();

        totalReceivedFromPOCL += amount;

        emit NUSCStakedNotified(msg.sender, amount);
    }

    /// @notice BNPL sends borrow fees to the vault.
    /// @dev With staking disabled, 100% goes to POCL.
    ///      With staking enabled, 70% is credited proportionally
    ///      to stakers and 30% goes to POCL.
    function receiveFees(
        uint256 borrowFee
    ) external onlyBNPL nonReentrant whenNotPaused {
        

        token.safeTransferFrom(msg.sender, address(this), borrowFee);

        totalProfit += borrowFee;

        uint256 stakerReward;
        uint256 poclShare;

        if (!stakingEnabled || totalStaked == 0) {
            poclShare = borrowFee;
        } else {
            uint256 nominalStakerShare = (borrowFee * STAKER_SHARE_BPS) / BPS;

            // Convert the nominal share into the accumulator.
            uint256 rewardPerTokenIncrement = (nominalStakerShare *
                ACC_PRECISION) / totalStaked;

            stakerReward =
                (rewardPerTokenIncrement * totalStaked) / ACC_PRECISION;

            rewardPerTokenStored += rewardPerTokenIncrement;
            totalRewardsLiability += stakerReward;

            // Any rounding dust is sent to POCL.
            poclShare = borrowFee - stakerReward;
        }

        if (poclShare > 0) {
            _sendFeeToPOCL(poclShare);
        }

        emit BorrowFeeReceived(borrowFee, stakerReward, poclShare);
    }

    // --------------------------------------------------
    // REWARD ACCOUNTING
    // --------------------------------------------------

    function outstandingBorrow() public view returns (uint256) {
        return totalBorrowed - totalRepaid;
    }

    function outstandingPoclAmount() public view returns (uint256) {
        if (totalWithdrawnByPOCL > totalReceivedFromPOCL) {
            revert InvalidPOCLAccounting();
        }
        return (totalReceivedFromPOCL - totalWithdrawnByPOCL);
    }

    /// @notice Net POCL capital retained plus current user-staked principal.
    /// @dev Used as the denominator for BNPL utilization.
    function totalCapital() public view returns (uint256) {
        return outstandingPoclAmount() + totalStaked;
    }

    function availableForBNPL() public view returns (uint256) {
        uint256 capital = totalCapital();
        uint256 borrowed = outstandingBorrow();

        return borrowed >= capital ? 0 : capital - borrowed;
    }

    /// @notice Returns the configured maximum and current BNPL utilization in BPS.
    /// @return maxUtilizationBps_ Admin-configured utilization limit.
    /// @return currentUtilizationBps Current utilization based on outstanding borrowing.
    function bnplUtilizationBps()
        public
        view
        returns (uint256 maxUtilizationBps_, uint256 currentUtilizationBps)
    {
        uint256 capital = totalCapital();

        maxUtilizationBps_ = maxBNPLUtilizationBps;

        if (capital == 0) {
            return (maxUtilizationBps_, 0);
        }

        currentUtilizationBps = (outstandingBorrow() * BPS) / capital;
    }

    function withdrawNUSCForPOCL(
        uint256 amount
    ) external onlyPOCL nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (amount > outstandingPoclAmount()) revert InsufficientFunding();

        // Never touch staker principal or accrued rewards
        if (
            token.balanceOf(address(this)) <
            amount + totalStaked + totalRewardsLiability
        ) revert InsufficientFunding();

        totalWithdrawnByPOCL += amount;

        token.safeTransfer(msg.sender, amount);

        emit FundsWithdrawnByPOCL(msg.sender, amount);
    }

    function getBorrowStats()
        external
        view
        returns (
            uint256 sentToBNPL,
            uint256 repaidByBNPL,
            uint256 pendingFromBNPL,
            uint256 feesPaidByBNPL
        )
    {
        sentToBNPL = totalBorrowed;
        repaidByBNPL = totalRepaid;
        pendingFromBNPL = outstandingBorrow();
        feesPaidByBNPL = totalProfit;
    }

    function calculateReward(
        uint256 _amount,
        uint256 _time
    ) public view returns (uint256) {
        return (_amount * APY() * _time) / (YEAR * BPS);
    }

    function pendingReward(address account) public view returns (uint256) {
        UserInfo storage user = users[account];

        uint256 accrued = 0;
        if (user.amount > 0 && user.lastUpdateTime != 0) {
            accrued = calculateReward(
                user.amount,
                block.timestamp - user.lastUpdateTime
            );
        }
        return user.rewardStored + accrued;
    }

    function _updateUserReward(address account) internal {
        UserInfo storage user = users[account];

        if (user.amount > 0 && user.lastUpdateTime != 0) {
            uint256 accrued = calculateReward(
                user.amount,
                block.timestamp - user.lastUpdateTime
            );
            if (accrued > 0) {
                user.rewardStored += accrued;
                user.totalRewardEarned += accrued;
                totalRewardsLiability += accrued;
            }
        }

        user.lastUpdateTime = block.timestamp;
    }

    function _sendFeeToPOCL(uint256 amount) internal {
        token.forceApprove(pocl, amount);
        IPoclContract(pocl).collectBorrowFee(amount);

        emit BorrowFeeSentToPOCL(pocl, amount);
    }

    function earned(address account) public view returns (uint256) {
        UserInfo storage user = users[account];

        uint256 accrued = (user.amount *
            (rewardPerTokenStored - user.rewardPerTokenPaid)) / ACC_PRECISION;

        return user.rewardStored + accrued;
    }

    function getUserInfo(
        address account
    ) external view returns (UserInfo memory info) {
        info = users[account];

        if (info.amount > 0 && info.lastUpdateTime != 0) {
            uint256 accrued = calculateReward(
                info.amount,
                block.timestamp - info.lastUpdateTime
            );
            info.rewardStored += accrued;
            info.totalRewardEarned += accrued;
        }
    }

    function getUserRewardStats(
        address account
    )
        external
        view
        returns (
            uint256 staked,
            uint256 pending,
            uint256 totalEarned,
            uint256 totalClaimed,
            uint256 withdrawable,
            uint256 yearlyEstimate
        )
    {
        UserInfo storage user = users[account];

        staked = user.amount;
        pending = pendingReward(account);
        totalEarned = user.totalRewardEarned + (pending - user.rewardStored);
        totalClaimed = user.rewardClaimed;
        withdrawable = staked + pending;
        yearlyEstimate = (staked * APY()) / BPS;
    }
    function APY() public view returns (uint256) {
        if (totalStaked == 0) return MIN_APY_BPS;

        uint256 apy = (totalStakerRewardsDistributed * BPS) / totalStaked;

        if (apy < MIN_APY_BPS) return MIN_APY_BPS;
        if (apy > MAX_APY_BPS) return MAX_APY_BPS;
        return apy;
    }

    // --------------------------------------------------
    // OWNER CONTROLS
    // --------------------------------------------------

    function setBNPLUtilizationLimitBps(
        uint256 newLimitBps
    ) external onlyOwner {
        if (newLimitBps > BPS) revert InvalidUtilizationLimit();

        uint256 oldLimitBps = maxBNPLUtilizationBps;
        maxBNPLUtilizationBps = newLimitBps;

        emit BNPLUtilizationLimitUpdated(oldLimitBps, newLimitBps);
    }

    function setFeeShares(
        uint256 stakerShareBps,
        uint256 poclShareBps
    ) external onlyOwner {
        if (stakerShareBps + poclShareBps != BPS) {
            revert InvalidFeeShares();
        }

        STAKER_SHARE_BPS = stakerShareBps;
        POCL_SHARE_BPS = poclShareBps;
    }

    function setStakingEnabled(bool enabled) external onlyOwner {
        stakingEnabled = enabled;
        if (enabled && lastProfitTime == 0) lastProfitTime = block.timestamp;
        emit StakingEnabledUpdated(enabled);
    }

    function setPOCL(address newPOCL) external onlyOwner {
        if (newPOCL == address(0)) revert ZeroAddress();
        pocl = newPOCL;
        emit POCLUpdated(newPOCL);
    }

    function setBNPL(address newBNPL) external onlyOwner {
        if (newBNPL == address(0)) revert ZeroAddress();
        bnpl = newBNPL;
        emit BNPLUpdated(newBNPL);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
