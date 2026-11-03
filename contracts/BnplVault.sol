// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IPoclContract {
    function collectBorrowFee(uint256 amount) external;
}

contract BnplVault is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // NUSC token
    IERC20 public immutable token =
        IERC20(0x14E35846856654693161d68Ea92caC952FF1b6f5);

    // ---------------- Constants ----------------
    uint256 public constant BPS = 10_000;
    uint256 public constant YEAR = 365 days;
    uint256 private constant ACC_PRECISION = 1e18;

    uint256 public constant MIN_APY_BPS = 300;
    uint256 public constant MAX_APY_BPS = 1_000;

    uint256 public constant MIN_EPOCH_LENGTH = 1 days;
    uint256 public constant MAX_EPOCH_LENGTH = 30 days;

    uint256 public constant MIN_WARMUP_PERIOD = 1 days;
    uint256 public constant MAX_WARMUP_PERIOD = 30 days;
    uint256 public constant MAX_PENDING_DEPOSITS = 50;

    // ---------------- Config ----------------
    uint256 public STAKER_SHARE_BPS = 7_000;
    uint256 public POCL_SHARE_BPS = 3_000;
    uint256 public maxBNPLUtilizationBps = 7_000;

    // Naye deposit kitne time baad reward-eligible honge (dynamic)
    uint256 public warmupPeriod = 7 days;

    // ---------------- Epoch (fee reporting + APY) ----------------
    uint256 public epochLength = 7 days;
    uint256 public epochAnchorEpoch;
    uint256 public pendingEpochLength;
    uint256 public pendingChangeTime;
    uint256 public pendingChangeEpoch;
    uint256 public epochStartTime;

    // ---------------- Addresses ----------------
    address public pocl;
    address public bnpl;

    // ---------------- Lending accounting ----------------
    uint256 public totalReceivedFromPOCL;
    uint256 public totalWithdrawnByPOCL;
    uint256 public totalBorrowed;
    uint256 public totalRepaid;

    // ---------------- Staking ----------------
    bool public stakingEnabled;
    uint256 public totalStaked; // active + pending (BNPL capital )
    uint256 public totalActiveStake; // sirf eligible stake (reward)
    uint256 public totalStakeClaimAmount;
    uint256 public totalRewardClaim;

    // ---------------- Profit / Rewards ----------------
    uint256 public totalProfit;
    uint256 public rewardPerTokenStored;
    uint256 public totalRewardsLiability;
    uint256 public totalStakerRewardsDistributed;

    struct UserInfo {
        uint256 amount; // active stake
        uint256 rewardStored;
        uint256 rewardClaimed;
        uint256 amountClaimed;
        uint256 lastClaimTime;
        uint256 totalRewardEarned;
        uint256 rewardPerTokenPaid;
        uint256 lastUpdateTime;
    }

    // 1 storage slot
    struct PendingDeposit {
        uint128 amount;
        uint64 activationTime;
    }

    // 1 storage slot
    struct RewardCheckpoint {
        uint64 timestamp;
        uint192 rewardPerToken;
    }

    mapping(address => UserInfo) public users;
    mapping(address => uint256) public pendingPrincipalOf;
    mapping(address => PendingDeposit[]) private pendingDeposits;

    mapping(uint256 => uint256) private pendingActivationAmount;
    mapping(uint256 => bool) private inHeap;
    uint256[] private activationTimeHeap;

    RewardCheckpoint[] private rewardCheckpoints;

    // epoch registers
    mapping(uint256 => uint256) public epochFees;
    mapping(uint256 => uint256) public epochStakerReward;
    mapping(uint256 => uint256) public epochPoclShare;

    // ---------------- Events ----------------
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 principal, uint256 reward);
    event RewardClaimed(address indexed user, uint256 amount);
    event FundsSentToBNPL(uint256 amount);
    event PrincipalReceived(uint256 amount);
    event StakingEnabledUpdated(bool enabled);
    event POCLUpdated(address indexed pocl);
    event BNPLUpdated(address indexed bnpl);
    event FundsWithdrawnByPOCL(address indexed pocl, uint256 amount);
    event NUSCStakedNotified(address indexed pocl, uint256 amount);
    event BorrowFeeSentToPOCL(address indexed pocl, uint256 amount);
    event BorrowFeeReceived(
        uint256 borrowFee,
        uint256 stakerReward,
        uint256 poclShare
    );
    event BNPLUtilizationLimitUpdated(uint256 oldLimitBps, uint256 newLimitBps);
    event EpochLengthScheduled(
        uint256 newLength,
        uint256 effectiveTime,
        uint256 effectiveEpoch
    );
    event WarmupPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    // ---------------- Errors ----------------
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientStake();
    error NoReward();
    error InsufficientFunding();
    error StakingDisabled();
    error Unauthorized();
    error InvalidUtilizationLimit();
    error InvalidEpochLength();
    error InvalidWarmupPeriod();
    error TooManyPendingDeposits();
    error InvalidPOCLAccounting();
    error InvalidFeeShares();

    // ---------------- Modifiers ----------------
    modifier onlyBNPL() {
        if (msg.sender != bnpl) revert Unauthorized();
        _;
    }

    modifier onlyPOCL() {
        if (msg.sender != pocl) revert Unauthorized();
        _;
    }

    modifier updateReward(address account) {
        _syncMaturedDeposits();
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

        PendingDeposit[] storage deposits = pendingDeposits[msg.sender];
        if (deposits.length >= MAX_PENDING_DEPOSITS)
            revert TooManyPendingDeposits();

        uint256 activationTime = block.timestamp + warmupPeriod;

        deposits.push(
            PendingDeposit({
                amount: amount.toUint128(),
                activationTime: activationTime.toUint64()
            })
        );
        pendingPrincipalOf[msg.sender] += amount;

        _scheduleActivation(activationTime, amount);

        totalStaked += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function unstake(
        uint256 amount
    ) external whenNotPaused nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        UserInfo storage user = users[msg.sender];

        uint256 pendingPrincipal = pendingPrincipalOf[msg.sender];
        uint256 principal = user.amount + pendingPrincipal;
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
            uint256 remaining = fromPrincipal;

            if (pendingPrincipal > 0) {
                PendingDeposit[] storage deposits = pendingDeposits[msg.sender];
                uint256 n = deposits.length;

                while (n > 0 && remaining > 0) {
                    PendingDeposit storage d = deposits[n - 1];
                    uint256 dAmt = d.amount;
                    uint256 take = remaining < dAmt ? remaining : dAmt;

                    pendingActivationAmount[d.activationTime] -= take;
                    remaining -= take;

                    if (take == dAmt) {
                        deposits.pop();
                        n--;
                    } else {
                        d.amount = uint128(dAmt - take);
                    }
                }

                pendingPrincipalOf[msg.sender] =
                    pendingPrincipal - (fromPrincipal - remaining);
            }

            if (remaining > 0) {
                user.amount -= remaining;
                totalActiveStake -= remaining;
            }

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

    function syncMatured() external {
        _syncMaturedDeposits();
    }

    function transferToken(
        address _token,
        address to,
        uint256 amount
    ) external onlyBNPL nonReentrant whenNotPaused {
        if (_token != address(token)) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        if (amount > availableForBNPL()) revert InsufficientFunding();

        if (token.balanceOf(address(this)) < amount + totalRewardsLiability)
            revert InsufficientFunding();

        totalBorrowed += amount;

        token.safeTransfer(to, amount);

        emit FundsSentToBNPL(amount);
    }

    function receivePrincipal(
        uint256 amount
    ) external onlyBNPL nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (amount > outstandingBorrow()) revert InsufficientFunding();

        token.safeTransferFrom(msg.sender, address(this), amount);

        totalRepaid += amount;

        emit PrincipalReceived(amount);
    }

    function notifyNUSCStaked(uint256 amount) external onlyPOCL nonReentrant {
        if (amount == 0) revert ZeroAmount();

        totalReceivedFromPOCL += amount;

        emit NUSCStakedNotified(msg.sender, amount);
    }

    function receiveFees(
        uint256 borrowFee
    ) external onlyBNPL nonReentrant whenNotPaused {
        if (borrowFee == 0) revert ZeroAmount();

        token.safeTransferFrom(msg.sender, address(this), borrowFee);

        _syncMaturedDeposits();
        _syncEpoch();

        totalProfit += borrowFee;

        uint256 stakerReward;
        uint256 poclShare;
        uint256 active = totalActiveStake;

        if (!stakingEnabled || active == 0) {
            poclShare = borrowFee;
        } else {
            uint256 nominalStakerShare = (borrowFee * STAKER_SHARE_BPS) / BPS;
            uint256 increment = (nominalStakerShare * ACC_PRECISION) / active;

            stakerReward = (increment * active) / ACC_PRECISION;

            uint256 newRpt = rewardPerTokenStored + increment;
            rewardPerTokenStored = newRpt;
            _pushCheckpoint(newRpt);

            totalRewardsLiability += stakerReward;
            totalStakerRewardsDistributed += stakerReward;

            poclShare = borrowFee - stakerReward;
        }

        uint256 e = currentEpoch();
        epochFees[e] += borrowFee;
        epochStakerReward[e] += stakerReward;
        epochPoclShare[e] += poclShare;

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

    function totalCapital() public view returns (uint256) {
        return outstandingPoclAmount() + totalStaked;
    }

    function availableForBNPL() public view returns (uint256) {
        uint256 maxBorrow = (totalCapital() * maxBNPLUtilizationBps) / BPS;
        uint256 borrowed = outstandingBorrow();

        return borrowed >= maxBorrow ? 0 : maxBorrow - borrowed;
    }

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

    function pendingReward(address account) public view returns (uint256) {
        UserInfo storage u = users[account];
        uint256 rpt = rewardPerTokenStored;

        uint256 total = u.rewardStored +
            (u.amount * (rpt - u.rewardPerTokenPaid)) / ACC_PRECISION;

        if (pendingPrincipalOf[account] == 0) return total;

        PendingDeposit[] storage deposits = pendingDeposits[account];
        uint256 n = deposits.length;
        for (uint256 i = 0; i < n; i++) {
            PendingDeposit storage d = deposits[i];
            if (d.amount > 0 && block.timestamp >= d.activationTime) {
                total +=
                    (uint256(d.amount) *
                        (rpt - _getRewardPerTokenAt(d.activationTime))) /
                    ACC_PRECISION;
            }
        }
        return total;
    }

    function unprocessedPrincipal(
        address account
    ) public view returns (uint256) {
        return pendingPrincipalOf[account];
    }

    function getPendingDeposits(
        address account
    ) external view returns (PendingDeposit[] memory) {
        return pendingDeposits[account];
    }

    function getUserInfo(
        address account
    ) external view returns (UserInfo memory info) {
        info = users[account];
        uint256 p = pendingReward(account);
        info.totalRewardEarned += p - info.rewardStored;
        info.rewardStored = p;
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
        staked = user.amount + pendingPrincipalOf[account];
        pending = pendingReward(account);
        totalEarned = user.totalRewardEarned + (pending - user.rewardStored);
        totalClaimed = user.rewardClaimed;
        withdrawable = staked + pending;
        yearlyEstimate = (staked * APY()) / BPS;
    }

    function APY() public view returns (uint256) {
        uint256 cur = currentEpoch();
        uint256 active = totalActiveStake;
        if (active == 0) return MIN_APY_BPS;
        if (cur < 2) return MIN_APY_BPS;

        uint256 apy = (epochStakerReward[cur - 1] * BPS * YEAR) /
            (active * epochLength);

        if (apy < MIN_APY_BPS) return MIN_APY_BPS;
        if (apy > MAX_APY_BPS) return MAX_APY_BPS;

        return apy;
    }

    function currentEpoch() public view returns (uint256) {
        if (epochStartTime == 0) return 0;

        if (pendingEpochLength != 0 && block.timestamp >= pendingChangeTime) {
            return
                pendingChangeEpoch +
                (block.timestamp - pendingChangeTime) / pendingEpochLength;
        }
        return
            epochAnchorEpoch + (block.timestamp - epochStartTime) / epochLength;
    }

    // --------------------------------------------------
    // INTERNAL: REWARD / WARMUP
    // --------------------------------------------------

    function _updateUserReward(address account) internal {
        UserInfo storage u = users[account];
        uint256 rpt = rewardPerTokenStored;

        uint256 accrued = (u.amount * (rpt - u.rewardPerTokenPaid)) /
            ACC_PRECISION;

        uint256 pendingPrincipal = pendingPrincipalOf[account];
        if (pendingPrincipal > 0) {
            PendingDeposit[] storage deposits = pendingDeposits[account];
            uint256 n = deposits.length;
            uint256 i = 0;
            uint256 moved;

            while (i < n) {
                PendingDeposit storage d = deposits[i];
                uint256 dAmt = d.amount;

                if (dAmt != 0 && block.timestamp < d.activationTime) {
                    i++;
                    continue;
                }

                if (dAmt != 0) {
                    accrued +=
                        (dAmt *
                            (rpt - _getRewardPerTokenAt(d.activationTime))) /
                        ACC_PRECISION;
                    moved += dAmt;
                }

                n--;
                if (i != n) deposits[i] = deposits[n];
                deposits.pop();
            }

            if (moved > 0) {
                u.amount += moved;
                pendingPrincipalOf[account] = pendingPrincipal - moved;
            }
        }

        if (accrued > 0) {
            u.rewardStored += accrued;
            u.totalRewardEarned += accrued;
        }
        u.rewardPerTokenPaid = rpt;
        u.lastUpdateTime = block.timestamp;
    }

    function _syncMaturedDeposits() internal {
        if (
            activationTimeHeap.length == 0 ||
            activationTimeHeap[0] > block.timestamp
        ) return;

        uint256 added;
        while (activationTimeHeap.length > 0) {
            uint256 t = activationTimeHeap[0];
            if (t > block.timestamp) break;

            added += pendingActivationAmount[t];
            delete pendingActivationAmount[t];
            delete inHeap[t];
            _popMinActivationTime();
        }

        if (added > 0) totalActiveStake += added;
    }

    function _scheduleActivation(
        uint256 activationTime,
        uint256 amount
    ) internal {
        pendingActivationAmount[activationTime] += amount;

        if (inHeap[activationTime]) return;
        inHeap[activationTime] = true;

        uint256 i = activationTimeHeap.length;
        activationTimeHeap.push(activationTime);

        while (i > 0) {
            uint256 parent = (i - 1) / 2;
            uint256 parentTime = activationTimeHeap[parent];
            if (parentTime <= activationTime) break;
            activationTimeHeap[i] = parentTime;
            i = parent;
        }
        activationTimeHeap[i] = activationTime;
    }

    function _popMinActivationTime() internal {
        uint256 len = activationTimeHeap.length;
        uint256 last = activationTimeHeap[len - 1];
        activationTimeHeap.pop();
        len--;

        if (len == 0) return;

        uint256 i = 0;
        while (true) {
            uint256 left = 2 * i + 1;
            if (left >= len) break;

            uint256 right = left + 1;
            uint256 child = left;
            uint256 childTime = activationTimeHeap[left];

            if (right < len) {
                uint256 rightTime = activationTimeHeap[right];
                if (rightTime < childTime) {
                    child = right;
                    childTime = rightTime;
                }
            }

            if (childTime >= last) break;
            activationTimeHeap[i] = childTime;
            i = child;
        }
        activationTimeHeap[i] = last;
    }

    function _pushCheckpoint(uint256 rpt) internal {
        uint256 len = rewardCheckpoints.length;
        if (
            len > 0 && rewardCheckpoints[len - 1].timestamp == block.timestamp
        ) {
            rewardCheckpoints[len - 1].rewardPerToken = rpt.toUint192();
        } else {
            rewardCheckpoints.push(
                RewardCheckpoint({
                    timestamp: uint64(block.timestamp),
                    rewardPerToken: rpt.toUint192()
                })
            );
        }
    }

    function _getRewardPerTokenAt(
        uint256 timestamp
    ) internal view returns (uint256) {
        uint256 low = 0;
        uint256 high = rewardCheckpoints.length;

        if (high == 0) return 0;

        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (rewardCheckpoints[mid].timestamp < timestamp) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        if (low == 0) return 0;
        return rewardCheckpoints[low - 1].rewardPerToken;
    }

    function _sendFeeToPOCL(uint256 amount) internal {
        token.forceApprove(pocl, amount);
        IPoclContract(pocl).collectBorrowFee(amount);

        emit BorrowFeeSentToPOCL(pocl, amount);
    }

    function _syncEpoch() internal {
        _applyPendingEpochLength();
    }

    function _applyPendingEpochLength() internal {
        if (pendingEpochLength != 0 && block.timestamp >= pendingChangeTime) {
            epochStartTime = pendingChangeTime;
            epochAnchorEpoch = pendingChangeEpoch;
            epochLength = pendingEpochLength;
            pendingEpochLength = 0;
        }
    }

    // --------------------------------------------------
    // OWNER CONTROLS
    // --------------------------------------------------

    function setWarmupPeriod(uint256 newPeriod) external onlyOwner {
        if (newPeriod < MIN_WARMUP_PERIOD || newPeriod > MAX_WARMUP_PERIOD)
            revert InvalidWarmupPeriod();

        emit WarmupPeriodUpdated(warmupPeriod, newPeriod);
        warmupPeriod = newPeriod;
    }

    function setEpochLength(uint256 newLength) external onlyOwner {
        if (newLength < MIN_EPOCH_LENGTH || newLength > MAX_EPOCH_LENGTH)
            revert InvalidEpochLength();

        // staking abhi shuru nahi hui, seedha set karo
        if (epochStartTime == 0) {
            epochLength = newLength;
            return;
        }

        _syncEpoch();
        uint256 cur = currentEpoch();

        pendingEpochLength = newLength;
        pendingChangeEpoch = cur + 1;
        pendingChangeTime =
            epochStartTime + (cur - epochAnchorEpoch + 1) * epochLength;

        emit EpochLengthScheduled(
            newLength,
            pendingChangeTime,
            pendingChangeEpoch
        );
    }

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
        if (enabled && epochStartTime == 0) {
            epochStartTime = block.timestamp;
            epochAnchorEpoch = 1;
        }
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
