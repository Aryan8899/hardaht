// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IPocl {
    function outstandingMMpoolAllocation() external view returns (uint256);
    function totalOutstandingAllocation() external view returns (uint256);
    function calculateDelta() external view returns (uint256 delta);
    /// @dev Same function BnplVault uses. POCL must pull `amount` via transferFrom.
    function collectMmFee(uint256 amount) external;
}

contract MMPool is ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public owner;

    uint256 public constant BPS = 10_000;
    uint256 public constant YEAR = 365 days;
    uint256 private constant ACC_PRECISION = 1e18;

    uint256 public constant MIN_APY_BPS = 300;
    uint256 public constant MAX_APY_BPS = 1_000;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error ZeroAmount();
    error NotBot();
    error NotSigner();
    error InvalidSigners();
    error InsufficientStake();
    error InsufficientLiquidity();
    error AlreadyApproved();
    error AlreadyExecuted();
    error InvalidProposal();

    error AlreadyBot();
    error NotABot();
    error MaxBotsReached();
    error NotOwner();
    error NothingToClaim();
    error NotPocl();
    error InvalidFeeShares();
    error InvalidPeriod();
    error PoclHasStake();
    error UnstakeDisabled();

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/
    IERC20 public immutable NUSC;

    uint256 public constant SIGNER_COUNT = 3;
    uint256 public constant THRESHOLD = 2;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/
    // --- stake accounting ---
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
    uint256 public totalUserStake;
    uint256 public poclStake;
    uint256 public totalRewardClaim;

    // --- profit split (MM bot profit: 70% stakers / 30% POCL) ---
    uint256 public STAKER_SHARE_BPS = 7_000;
    uint256 public POCL_SHARE_BPS = 3_000;

    uint256 public rewardPerTokenStored;
    // staker rewards that are already deposited by bots but not yet claimed.
    // These tokens sit in the contract but are NOT liquidity.
    uint256 public totalRewardsLiability;
    uint256 public totalStakerRewardsDistributed;
    uint256 public totalProfitSentToPocl;

    // --- APY (informational) ---
    uint256 public apyPeriod = 30 days;
    uint256 public periodStart;
    uint256 public periodRewards;
    uint256 public lastPeriodApyBps;

    // --- unstake switch (false by default, owner enables) ---
    bool public unstakeEnabled;

    // --- pocl ---
    address public pocl;

    // --- bot accounting ---
    uint256 public constant MAX_BOTS = 10;
    address[] private bots;
    uint256 public totalProfitFromBot;

    // --- multisig (2 of 3) ---
    address[SIGNER_COUNT] public signers;
    mapping(address => bool) public isSigner;
    mapping(address => uint256) private botIndex;
    mapping(address => uint256) public botProfit;

    enum Action {
        ADD_BOT,
        REMOVE_BOT
    }

    struct Proposal {
        Action action;
        address target;
        uint8 approvals;
        bool executed;
    }

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasApproved;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Staked(address indexed account, uint256 amount, bool byPocl);
    event Unstaked(address indexed account, uint256 amount, bool byPocl);

    event ProposalCreated(
        uint256 indexed id,
        Action action,
        address target,
        address indexed proposer
    );
    event ProposalApproved(
        uint256 indexed id,
        address indexed signer,
        uint8 approvals
    );
    event ProposalExecuted(uint256 indexed id);
    event RewardClaimed(address indexed user, uint256 reward);
    event ProfitDeposited(
        address indexed bot,
        uint256 amount,
        uint256 botTotal,
        uint256 allBotsTotal
    );
    event ProfitSplit(
        address indexed bot,
        uint256 totalProfit,
        uint256 stakerShare,
        uint256 poclShare
    );
    event ProfitSentToPocl(address indexed pocl, uint256 amount);
    event FeeSharesUpdated(uint256 stakerShareBps, uint256 poclShareBps);
    event PoclSet(address indexed oldPocl, address indexed newPocl);
    event UnstakeEnabledUpdated(bool enabled);
    event BotAdded(address indexed bot);
    event BotRemoved(address indexed bot);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyBot() {
        if (botIndex[msg.sender] == 0) revert NotBot();
        _;
    }

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert NotSigner();
        _;
    }
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyPocl() {
        if (msg.sender != pocl) revert NotPocl();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        address nusc,
        address _pocl,
        address[SIGNER_COUNT] memory _signers
    ) {
        if (nusc == address(0) || _pocl == address(0)) revert ZeroAddress();

        NUSC = IERC20(nusc);
        pocl = _pocl;
        owner = msg.sender;

        for (uint256 i = 0; i < SIGNER_COUNT; i++) {
            address s = _signers[i];
            if (s == address(0) || isSigner[s]) revert InvalidSigners();
            isSigner[s] = true;
            signers[i] = s;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    function stake(uint256 amount) external nonReentrant {
        _updateReward(msg.sender);

        uint256 received = _pullTokens(msg.sender, amount);

        users[msg.sender].amount += received;

        if (msg.sender == pocl) {
            poclStake += received;
        } else {
            totalUserStake += received;
        }

        emit Staked(msg.sender, received, msg.sender == pocl);
    }

    /// @dev New pocl and old pocl must hold no stake here, otherwise the
    ///      poclStake / totalUserStake accounting would break.
    function setPocl(address newPocl) external onlyOwner {
        if (newPocl == address(0)) revert ZeroAddress();
        if (users[pocl].amount != 0 || users[newPocl].amount != 0)
            revert PoclHasStake();

        address old = pocl;
        pocl = newPocl;
        emit PoclSet(old, newPocl);
    }

    /// @notice Owner switch: unstake and POCL withdraw work only when true.
    function setUnstakeEnabled(bool enabled) external onlyOwner {
        unstakeEnabled = enabled;
        emit UnstakeEnabledUpdated(enabled);
    }

    function setFeeShares(
        uint256 stakerShareBps,
        uint256 poclShareBps
    ) external onlyOwner {
        if (stakerShareBps + poclShareBps != BPS) revert InvalidFeeShares();
        STAKER_SHARE_BPS = stakerShareBps;
        POCL_SHARE_BPS = poclShareBps;
        emit FeeSharesUpdated(stakerShareBps, poclShareBps);
    }

    function setApyPeriod(uint256 newPeriod) external onlyOwner {
        if (newPeriod < 1 days) revert InvalidPeriod();
        apyPeriod = newPeriod;
    }

    /// @notice Unstake principal + reward. Reward is taken first, then principal.
    /// @dev Works only when unstakeEnabled is true. Paid instantly, no queue.
    function unstake(uint256 amount) external nonReentrant {
        if (!unstakeEnabled) revert UnstakeDisabled();
        if (amount == 0) revert ZeroAmount();

        _updateReward(msg.sender);
        UserInfo storage u = users[msg.sender];

        uint256 reward = u.rewardStored;
        if (amount > u.amount + reward) revert InsufficientStake();

        // pehle reward, phir principal
        uint256 rewardPart = amount <= reward ? amount : reward;
        uint256 principalPart = amount - rewardPart;

        // ---- effects ----
        if (rewardPart > 0) {
            u.rewardStored -= rewardPart;
            u.rewardClaimed += rewardPart;
            u.lastClaimTime = block.timestamp;
            totalRewardClaim += rewardPart;
            totalRewardsLiability -= rewardPart;
        }

        if (principalPart > 0) {
            u.amount -= principalPart;
            u.amountClaimed += principalPart;
            if (msg.sender == pocl) poclStake -= principalPart;
            else totalUserStake -= principalPart;
        }

        // ---- interactions ----
        NUSC.safeTransfer(msg.sender, amount);

        if (rewardPart > 0) emit RewardClaimed(msg.sender, rewardPart);
        if (principalPart > 0)
            emit Unstaked(msg.sender, principalPart, msg.sender == pocl);
    }

    function notifyNUSCStaked(uint256 amount) external onlyPocl nonReentrant {
        if (amount == 0) revert ZeroAmount();

        _updateReward(msg.sender);
        users[msg.sender].amount += amount;
        poclStake += amount;

        emit Staked(msg.sender, amount, true);
    }

    function withdrawNUSCForPOCL(
        uint256 amount,
        address recipient
    ) external onlyPocl nonReentrant {
        if (!unstakeEnabled) revert UnstakeDisabled();
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();

        UserInfo storage u = users[msg.sender];
        if (u.amount < amount || poclStake < amount) revert InsufficientStake();

        if (availableLiquidity() < amount) revert InsufficientLiquidity();

        u.amount -= amount;
        poclStake -= amount;
        u.amountClaimed += amount;

        NUSC.safeTransfer(recipient, amount);

        emit Unstaked(msg.sender, amount, true);
    }

    function claimReward() external nonReentrant {
        _updateReward(msg.sender);

        UserInfo storage u = users[msg.sender];
        uint256 reward = u.rewardStored;
        if (reward == 0) revert NothingToClaim();

        u.rewardStored = 0;
        u.rewardClaimed += reward;
        u.lastClaimTime = block.timestamp;
        totalRewardClaim += reward;
        totalRewardsLiability -= reward;

        NUSC.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }

    /*//////////////////////////////////////////////////////////////
                              BOT WALLET
    //////////////////////////////////////////////////////////////*/

    /// @notice MM bot deposits 100% profit. Split: STAKER_SHARE to stakers
    function depositProfit(uint256 amount) external onlyBot nonReentrant {
        uint256 received = _pullTokens(msg.sender, amount);

        botProfit[msg.sender] += received;
        totalProfitFromBot += received;

        uint256 stakerReward = (received * STAKER_SHARE_BPS) / BPS;
        uint256 poclShare = received - stakerReward;

        if (totalUserStake > 0) {
            uint256 increment = (stakerReward * ACC_PRECISION) / totalUserStake;

            stakerReward = (increment * totalUserStake) / ACC_PRECISION;

            rewardPerTokenStored += increment;
            totalRewardsLiability += stakerReward;
            totalStakerRewardsDistributed += stakerReward;

            if (periodStart == 0) periodStart = block.timestamp;
            _rollPeriod();
            periodRewards += stakerReward;

            // Rounding dust goes to POCL
            poclShare = received - stakerReward;
        } 

        if (poclShare > 0) _sendProfitToPocl(poclShare);

        emit ProfitDeposited(
            msg.sender,
            received,
            botProfit[msg.sender],
            totalProfitFromBot
        );

        emit ProfitSplit(msg.sender, received, stakerReward, poclShare);
    }

    function _sendProfitToPocl(uint256 amount) private {
        totalProfitSentToPocl += amount;
        NUSC.forceApprove(pocl, amount);
        IPocl(pocl).collectMmFee(amount);
        emit ProfitSentToPocl(pocl, amount);
    }

    function isBot(address account) public view returns (bool) {
        return botIndex[account] != 0;
    }

    function getBots() external view returns (address[] memory) {
        return bots;
    }

    function botCount() external view returns (uint256) {
        return bots.length;
    }

    /*//////////////////////////////////////////////////////////////
                       2-OF-3 MULTISIG (BOT MGMT)
    //////////////////////////////////////////////////////////////*/

    function proposeAddBot(
        address newBot
    ) external onlySigner returns (uint256 id) {
        if (newBot == address(0)) revert ZeroAddress();
        if (isBot(newBot)) revert AlreadyBot();
        id = _createProposal(Action.ADD_BOT, newBot);
    }

    function proposeRemoveBot(
        address bot
    ) external onlySigner returns (uint256 id) {
        if (!isBot(bot)) revert NotABot();
        id = _createProposal(Action.REMOVE_BOT, bot);
    }

    function approve(uint256 id) external onlySigner {
        _approve(id);
    }

    function _createProposal(
        Action action,
        address target
    ) private returns (uint256 id) {
        id = ++proposalCount;
        proposals[id] = Proposal({
            action: action,
            target: target,
            approvals: 0,
            executed: false
        });

        emit ProposalCreated(id, action, target, msg.sender);
        _approve(id);
    }

    function _approve(uint256 id) private {
        if (id == 0 || id > proposalCount) revert InvalidProposal();
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        if (hasApproved[id][msg.sender]) revert AlreadyApproved();

        hasApproved[id][msg.sender] = true;
        p.approvals += 1;

        emit ProposalApproved(id, msg.sender, p.approvals);

        if (p.approvals >= THRESHOLD) {
            _execute(id, p);
        }
    }

    function _execute(uint256 id, Proposal storage p) private {
        p.executed = true;

        if (p.action == Action.ADD_BOT) {
            _addBot(p.target);
        } else {
            _removeBot(p.target);
        }

        emit ProposalExecuted(id);
    }

    function _addBot(address bot) private {
        if (isBot(bot)) revert AlreadyBot();
        if (bots.length >= MAX_BOTS) revert MaxBotsReached();

        bots.push(bot);
        botIndex[bot] = bots.length;

        emit BotAdded(bot);
    }

    function _removeBot(address bot) private {
        uint256 idx = botIndex[bot];
        if (idx == 0) revert NotABot();

        uint256 lastIdx = bots.length;
        if (idx != lastIdx) {
            address lastBot = bots[lastIdx - 1];
            bots[idx - 1] = lastBot;
            botIndex[lastBot] = idx;
        }
        bots.pop();
        delete botIndex[bot];

        emit BotRemoved(bot);
    }

    /*//////////////////////////////////////////////////////////////
                           REWARD ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function _updateReward(address account) internal {
        UserInfo storage u = users[account];

        // POCL is not part of the staker accumulator (it gets its 30% directly)
        if (account != pocl && u.amount > 0) {
            uint256 accrued = (u.amount *
                (rewardPerTokenStored - u.rewardPerTokenPaid)) / ACC_PRECISION;

            if (accrued > 0) {
                u.rewardStored += accrued;
                u.totalRewardEarned += accrued;
            }
        }

        u.rewardPerTokenPaid = rewardPerTokenStored;
        u.lastUpdateTime = block.timestamp;
    }

    function pendingReward(address account) public view returns (uint256) {
        UserInfo storage u = users[account];
        if (account == pocl || u.amount == 0) return u.rewardStored;

        uint256 accrued = (u.amount *
            (rewardPerTokenStored - u.rewardPerTokenPaid)) / ACC_PRECISION;

        return u.rewardStored + accrued;
    }

    function getDailyReward(address account) external view returns (uint256) {
        UserInfo storage u = users[account];
        if (account == pocl || u.amount == 0) return 0;
        return (u.amount * APY()) / BPS / 365;
    }

    /// @dev Informational APY based on actual staker rewards in the current period.
    function APY() public view returns (uint256) {
        if (periodStart == 0 || totalUserStake == 0) return MIN_APY_BPS;

        uint256 elapsed = block.timestamp - periodStart;
        if (elapsed == 0) return MIN_APY_BPS;

        uint256 apy = (periodRewards * BPS * YEAR) / (totalUserStake * elapsed);

        if (apy < MIN_APY_BPS) return MIN_APY_BPS;
        if (apy > MAX_APY_BPS) return MAX_APY_BPS;
        return apy;
    }

    function _rollPeriod() internal {
        if (periodStart == 0) return;

        uint256 elapsed = block.timestamp - periodStart;

        if (elapsed >= apyPeriod) {
            if (totalUserStake > 0) {
                lastPeriodApyBps =
                    (periodRewards * BPS * YEAR) / (totalUserStake * elapsed);
            }
            periodRewards = 0;
            periodStart = block.timestamp;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function totalStaked() external view returns (uint256) {
        return totalUserStake + poclStake;
    }

    function getSigners() external view returns (address[SIGNER_COUNT] memory) {
        return signers;
    }

    function _pullTokens(
        address from,
        uint256 amount
    ) private returns (uint256 received) {
        if (amount == 0) revert ZeroAmount();
        uint256 beforeBal = NUSC.balanceOf(address(this));
        NUSC.safeTransferFrom(from, address(this), amount);
        received = NUSC.balanceOf(address(this)) - beforeBal;
    }

    /// @notice Liquidity = POCL stake + user stake.
    ///         MM profit reserved for stakers (totalRewardsLiability) is not included.
    function availableLiquidity() public view returns (uint256) {
        return totalUserStake + poclStake;
    }

    function getPoclAllocation()
        external
        view
        returns (
            uint256 mmPoolAllocation,
            uint256 totalAllocation,
            uint256 delta
        )
    {
        mmPoolAllocation = IPocl(pocl).outstandingMMpoolAllocation();
        totalAllocation = IPocl(pocl).totalOutstandingAllocation();
        delta = IPocl(pocl).calculateDelta();
    }

    function getUserStaked(address account) external view returns (uint256) {
        return users[account].amount;
    }
}
