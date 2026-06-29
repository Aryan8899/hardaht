/**
 *Submitted for verification at BscScan.com on 2025-04-22
*/

/**
 *Submitted for verification at BscScan.com on 2025-01-18
*/

// SPDX-License-Identifier: MIT

// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.27;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.0/contracts/utils/Address.sol



pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// File: multisignWallet.sol


pragma solidity ^0.8.30;




contract MultisignWallet is Ownable {
    using Address for address;

    struct WithdrawalRequest {
        uint256 txId;
        address tokenAddress;
        address requester;
        address toAddress;
        uint256 amount;
        uint256 expiryTime;
        bool isPending;
        uint256 approvalCount;
        mapping(address => bool) approvals;
    }

     struct ActionRequest {
        uint256 actionId;
        address requester;
        address targetWallet;
        uint256 approvalCount;
        uint256 timestamp;
        bool isPending;
        ActionType actionType;
        mapping(address => bool) approvals;
    }

    enum ActionType{ ADD, REMOVE, REPLACE}

    mapping (uint256 => ActionRequest) public actions;
    mapping(uint256 => WithdrawalRequest) public requests;
    mapping(address => bool) public isOwner;
    mapping(address => bool) public trustedContracts;

    address[] public owners;
    uint256 public approveRequired;
    uint256 public requestCount;
    uint256 public actionCount;
    bool public isActionRequestActive;
    bool public isWithdrawlActive;

    event WithdrawalRequestCreated(uint256 txId, address token, address requester, address toAddress, uint256 amount, uint256 expiryTime);
    event WithdrawalRequestExpired(uint256 txId);
    event WithdrawalRequestExecuted(uint256 txId, address token, address toAddress, uint256 amount);

    event ActionRequestCreated(uint256 actionId, address requester, ActionType actionType, address targetWallet);
    event ActionRequestApproved(uint256 actionId, address approver);
    event ActionExecuted(uint256 actionId, ActionType actionType, address targetWallet);

    constructor(address[] memory _owners, uint _approveRequired) Ownable(msg.sender) {
        require(_owners.length > 1 && _owners.length >= _approveRequired, "Approvers should be less than Owners");

        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "invalid owner");
            require(!isOwner[owner], "owner not unique");

            isOwner[owner] = true;
            owners.push(owner);
        }
        approveRequired = _approveRequired;
    }

    modifier initializeOwner() {
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier notContract() {
        require(!msg.sender.isContract(), "Contract is not allowed to swap");
        _;
    }

    receive() external payable {}

    function isETH(address _tokenAddress) private pure returns (bool) {
        return _tokenAddress == address(0); 
    }

    function createWithdrawalRequest(address _tokenAddress, address toAddress, uint256 amount) external  returns (uint256 txId) {
        
        require(!isActionRequestActive, "An action request is pending, Please resolve first");
        // Check if there is any pending request

        if (requestCount > 0) {
            WithdrawalRequest storage existingRequest = requests[requestCount];
            if (existingRequest.isPending && block.timestamp <= existingRequest.expiryTime) {
                revert("A request is already pending and valid.");
            }
            if (existingRequest.isPending && block.timestamp > existingRequest.expiryTime) {
                existingRequest.isPending = false;
                emit WithdrawalRequestExpired(existingRequest.txId);
            }
        }

        // Check if the token is ETH (address(0) is ETH) 
        if (isETH(_tokenAddress)) {
            require(address(this).balance >= amount, "Insufficient ETH balance");
        } else {
            require(IERC20(_tokenAddress).balanceOf(address(this)) >= amount, "Insufficient ERC20 balance");
        }

        // Increment request count
        requestCount++;
        txId = requestCount;

        WithdrawalRequest storage newRequest = requests[txId];
        newRequest.tokenAddress = _tokenAddress;
        newRequest.requester = msg.sender;
        newRequest.toAddress = toAddress;
        newRequest.amount = amount;
        newRequest.expiryTime = block.timestamp + 1 hours;
        newRequest.isPending = true;
        newRequest.txId = txId;
        newRequest.approvalCount = 0;

        isWithdrawlActive = true;

        emit WithdrawalRequestCreated(txId, _tokenAddress, msg.sender, toAddress, amount, block.timestamp + 1 hours);



if (trustedContracts[msg.sender]) {
        executeWithdrawal(txId);
        return txId;
    }
        return txId;
    }

    // This function allows an owner to approve a withdrawal request
    function approveWithdrawal(uint256 txId) external initializeOwner {
        WithdrawalRequest storage request = requests[txId];
        require(request.isPending, "Request is not pending");
        require(!request.approvals[msg.sender], "You have already approved this request");
        require(msg.sender != request.requester,"You are the Withdrawl Creator");

        request.approvals[msg.sender] = true;
        request.approvalCount++;

        // If enough approvals are reached, execute the withdrawal
        if (request.approvalCount >= approveRequired) {
            executeWithdrawal(txId);
        }
    }

    function executeWithdrawal(uint256 txId) internal {
    WithdrawalRequest storage request = requests[txId];
    
    // trusted contract ke liye approval check skip
    if (!trustedContracts[request.requester]) {
        require(request.approvalCount >= approveRequired, "Not enough approvals");
    }

    request.isPending = false;
    isWithdrawlActive = false;

    if (isETH(request.tokenAddress)) {
        (bool success, ) = request.toAddress.call{value: request.amount}("");
        require(success, "ETH transfer failed");
    } else {
        require(IERC20(request.tokenAddress).transfer(request.toAddress, request.amount), "ERC20 transfer failed");
    }

    emit WithdrawalRequestExecuted(txId, request.tokenAddress, request.toAddress, request.amount);
}

    function createActionRequest (ActionType _actionType, address _wallet) external initializeOwner {
       require(_actionType == ActionType.ADD || _actionType == ActionType.REMOVE || _actionType == ActionType.REPLACE, "Invalid action type");
       require(!isWithdrawlActive, "A withdrawal request is active, cannot create action request");
       require(!isActionRequestActive, "An action request is already pending");

            require(_wallet != address(0), "Invalid wallet address");

            if (_actionType == ActionType.ADD || _actionType == ActionType.REPLACE){
                require(!isOwner[_wallet], "Wallet is already an owner");
            }else if (_actionType == ActionType.REMOVE) {
                require(isOwner[_wallet], "Wallet is not an owner");
            }else {
               revert("Invalid action type");
            }

        actionCount++;
        uint256 actionId = actionCount;

            ActionRequest storage newAction = actions[actionId];
         newAction.actionId = actionId;
         newAction.requester = msg.sender;
         newAction.targetWallet = _wallet;
         newAction.timestamp = block.timestamp;
         newAction.isPending = true;
         newAction.actionType = _actionType;
         newAction.approvalCount = 0;

        isActionRequestActive = true;
    }

    function approveActionRequest(uint256 actionId) external initializeOwner{
         ActionRequest storage actionRequest = actions[actionId];
        require(actionRequest.isPending, "Action request is not pending");
        require(!actionRequest.approvals[msg.sender], "You have already approved this action request");

        if (actionRequest.actionType == ActionType.ADD || actionRequest.actionType == ActionType.REPLACE) {
        require(msg.sender != actionRequest.requester, "Creator cannot approve ADD or REPLACE actions");
        } else if (actionRequest.actionType == ActionType.REMOVE) {
        require(msg.sender != actionRequest.targetWallet, "Targeted wallet cannot approve REMOVE actions");
        }

        actionRequest.approvals[msg.sender] = true;
        actionRequest.approvalCount++;

        emit ActionRequestApproved(actionId, msg.sender);
         if (actionRequest.approvalCount >= approveRequired) {
              executeAction(actionId);
        }
    }

    function executeAction(uint256 actionId) internal {
       ActionRequest storage actionRequest = actions[actionId];
       require(actionRequest.approvalCount >= approveRequired, "Not enough approvals");
       require(actionRequest.isPending, "Action already executed");

       actionRequest.isPending = false;
       isActionRequestActive = false;

      if (actionRequest.actionType == ActionType.ADD) {

        isOwner[actionRequest.targetWallet] = true;
        owners.push(actionRequest.targetWallet);
        approveRequired = owners.length - 1;
     } else if (actionRequest.actionType == ActionType.REMOVE) {
       
        isOwner[actionRequest.targetWallet] = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == actionRequest.targetWallet) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
     } else if (actionRequest.actionType == ActionType.REPLACE) {
       
        isOwner[actionRequest.targetWallet] = true;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == actionRequest.requester) {
                owners[i] = actionRequest.targetWallet;
                break;
            }
        }
        isOwner[actionRequest.requester] = false;
     }
      if (approveRequired >= owners.length) {
        approveRequired = owners.length - 1;
      }
    }

    function getWithdrawalApprovers(uint256 txId) external view returns (address[] memory) {
       WithdrawalRequest storage request = requests[txId];
       address[] memory approvers = new address[](request.approvalCount);
       uint256 index = 0;

      for (uint256 i = 0; i < owners.length; i++) {
        if (request.approvals[owners[i]]) {
            approvers[index] = owners[i];
            index++;
        }
      }
      return approvers; 
    }

    function getActionApprovers(uint256 actionId) external view returns (address[] memory) {
       ActionRequest storage action = actions[actionId];
       address[] memory approvers = new address[](action.approvalCount);
       uint256 index = 0;

     for (uint256 i = 0; i < owners.length; i++) {
        if (action.approvals[owners[i]]) {
            approvers[index] = owners[i];
            index++;
        }
     }
      return approvers;
    }


    function setTrustedContract(address _contract, bool _trusted) external onlyOwner {
    require(_contract != address(0), "invalid address");
    trustedContracts[_contract] = _trusted;
}

}