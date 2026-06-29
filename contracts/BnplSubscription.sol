// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";  
import "@openzeppelin/contracts/utils/Pausable.sol";          
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract BnplSubscription is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    IERC20 public immutable USDT;

    struct Tier {
        uint256 id;
        uint32 multiplier;    
        uint256 usdtPrice;     
        uint64 duration;
        uint256 maxTradeAmount;   // includes leverage
        bool active;
    }

    struct Subscription {
        uint256 tierId;
        uint32 multiplier;
        uint256 subscriptionFee; 
        uint256 maxTradeAmount;   // includes leverage
        uint64 start;
        uint64 expires;
        bool isSubscribe;
        bool isDiscount;
        bool isUpgrade;
    }

    uint256 private _nextTierId;
    mapping(uint256 => Tier) public tiers;
    mapping(address => bool) public isUser;
    mapping(address => Subscription) public subscriptions;
    bool public free2xEnabled = true;

    EnumerableSet.UintSet private _tierIds;

    event TierAdded(uint256 indexed tierId, uint32 multiplier, uint256 bnbPrice, uint64 duration, uint maxTradeAmount);
    event TierUpdated(uint256 indexed tierId);
    event TierToggled(uint256 indexed tierId, bool active);
    event Subscribed(address indexed user, uint256 indexed tierId, uint32 multiplier, uint256 subscriptionFee, uint64 expires);

    event UserWhitelisted(address indexed pool, bool allowed);

    error TierNotActive(uint256 tierId);

   constructor(address usdt) Ownable(msg.sender) {
        require(usdt != address(0), "Zero USDT");
        USDT = IERC20(usdt);

        _nextTierId = 1;
        _addTierInternal(2, 0.1 ether, 5, 200 ether);
        _addTierInternal(5, 0.2 ether, 5, 500 ether);
        _addTierInternal(10, 0.3 ether, 5, 1000 ether);
    }

           /* ========== ADMIN SET FUNCTION ========== */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function addTier(uint32 multiplier,  uint256 usdtPrice, uint64 duration,uint256 maxTradeAmount, bool active) external onlyOwner {
       _addTierInternal(multiplier, usdtPrice, duration, maxTradeAmount);
        uint256 id = _nextTierId - 1;
        tiers[id].active = active;
        emit TierAdded(id, multiplier, usdtPrice, duration,maxTradeAmount );
    }

    function updateTier(uint256 tierId, uint32 multiplier, uint256 usdtPrice, uint256 maxTradeAmount, uint64 duration) external onlyOwner {
        _requireTierExists(tierId);
        Tier storage t = tiers[tierId];
        t.multiplier = multiplier;
        t.usdtPrice = usdtPrice;
        t.maxTradeAmount = maxTradeAmount;
        t.duration = duration;
        emit TierUpdated(tierId);
    }

    function setTierActive(uint256 tierId, bool active) external onlyOwner {
        _requireTierExists(tierId);
        tiers[tierId].active = active;
        emit TierToggled(tierId, active);
    }

    function removeTier(uint256 tierId) external onlyOwner {
        _requireTierExists(tierId);
        delete tiers[tierId];
        _tierIds.remove(tierId);
    }

       /* ========== INTERNAL FUNCTION ========== */

    function _addTierInternal(uint32 multiplier, uint256 usdtPrice, uint64 durationInDays,uint256 maxTradeAmount) internal {
        require(multiplier > 0, "multiplier 0");
        require(maxTradeAmount > 0, "max trade 0");

           uint256 length = _tierIds.length();
        for (uint256 i = 0; i < length; i++) {
           uint256 tierId = _tierIds.at(i);
           if (tiers[tierId].multiplier == multiplier) {
            revert("Multiplier already exists");
           }
        }

        uint256 id = _nextTierId++;
        tiers[id] = Tier({
            id: id,
            multiplier: multiplier,
            usdtPrice: usdtPrice,
            duration: uint64(durationInDays * 1 days),
            maxTradeAmount: maxTradeAmount,
            active: true
        });
        _tierIds.add(id);
    }

    function _requireTierExists(uint256 tierId) internal view {
        require(_tierIds.contains(tierId)," Tier Not Exist");
    }

    function setFree2xEnabled(bool _status) external onlyOwner {
        free2xEnabled = _status;
    }
    
              /* ========== Main FUNCTION ========== */

    function subscribe(uint256 tierId) external nonReentrant whenNotPaused {
       _requireTierExists(tierId);

       Tier memory tier = tiers[tierId];
       if (!tier.active) revert TierNotActive(tierId);

        // ===== NEW GLOBAL LOGIC =====
       uint256 fee = tier.usdtPrice;
       bool freeSubscription = false;

       if (free2xEnabled && tier.multiplier == 2) {
          fee = 0;
          freeSubscription = true;
       }

       // ===== PAYMENT =====
       if (fee > 0) {
          USDT.safeTransferFrom(msg.sender, address(this), fee);
      }

        // ===== SUBSCRIPTION STORAGE =====
        Subscription storage sub = subscriptions[msg.sender];

       uint64 startTime = uint64(block.timestamp);
       uint64 expiryTime = startTime + tier.duration;

        sub.tierId = tierId;
        sub.multiplier = tier.multiplier;
        sub.subscriptionFee = fee;
        sub.start = startTime;
        sub.expires = expiryTime;
        sub.isSubscribe = true;
        sub.maxTradeAmount = tier.maxTradeAmount;
        sub.isDiscount = freeSubscription;
        sub.isUpgrade = false;

       emit Subscribed(msg.sender, tierId, tier.multiplier, fee, expiryTime);
    }

     /* ========== VIEW FUNCTION ========== */

    function getTierIds() public view returns (uint256[] memory) {
        return _tierIds.values();
    }

    function getUserMaxTrade(address user) external view returns (uint256) {
        Subscription memory sub = subscriptions[user];
       
       if (sub.isSubscribe && sub.expires > block.timestamp) {
           Tier memory tier = tiers[sub.tierId];
            if (tier.active) {
               return sub.maxTradeAmount;
            }
        }
        return 0;
    }

    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "zero");
        IERC20(token).safeTransfer(to, amount);
    }

}