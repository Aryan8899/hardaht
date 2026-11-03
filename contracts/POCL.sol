// File: @openzeppelin/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

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

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

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

// File: @openzeppelin/contracts/access/Ownable2Step.sol

// OpenZeppelin Contracts (last updated v5.1.0) (access/Ownable2Step.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This extension of the {Ownable} contract includes a two-step mechanism to transfer
 * ownership, where the new owner must call {acceptOwnership} in order to replace the
 * old one. This can help prevent common mistakes, such as transfers of ownership to
 * incorrect accounts, or to contracts that are unable to interact with the
 * permission system.
 *
 * The initial owner is specified at deployment time in the constructor for `Ownable`. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     *
     * Setting `newOwner` to the zero address is allowed; this can be used to cancel an initiated ownership transfer.
     */
    function transferOwnership(
        address newOwner
    ) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        if (pendingOwner() != sender) {
            revert OwnableUnauthorizedAccount(sender);
        }
        _transferOwnership(sender);
    }
}

// File: @openzeppelin/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

pragma solidity ^0.8.20;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(
        bytes32 slot
    ) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(
        bytes32 slot
    ) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(
        bytes32 slot
    ) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(
        bytes32 slot
    ) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(
        bytes32 slot
    ) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(
        bytes32 slot
    ) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(
        string storage store
    ) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(
        bytes32 slot
    ) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(
        bytes storage store
    ) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}

// File: @openzeppelin/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.5.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 *
 * IMPORTANT: Deprecated. This storage-based reentrancy guard will be removed and replaced
 * by the {ReentrancyGuardTransient} variant in v6.0.
 *
 * @custom:stateless
 */
abstract contract ReentrancyGuard {
    using StorageSlot for bytes32;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /**
     * @dev A `view` only version of {nonReentrant}. Use to block view functions
     * from being called, preventing reading from inconsistent contract state.
     *
     * CAUTION: This is a "view" modifier and does not change the reentrancy
     * status. Use it only on view functions. For payable or non-payable functions,
     * use the standard {nonReentrant} modifier instead.
     */
    modifier nonReentrantView() {
        _nonReentrantBeforeView();
        _;
    }

    function _nonReentrantBeforeView() private view {
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        _nonReentrantBeforeView();

        // Any calls to nonReentrant after this point will fail
        _reentrancyGuardStorageSlot().getUint256Slot().value = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _reentrancyGuardStorageSlot().getUint256Slot().value = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyGuardStorageSlot().getUint256Slot().value == ENTERED;
    }

    function _reentrancyGuardStorageSlot()
        internal
        pure
        virtual
        returns (bytes32)
    {
        return REENTRANCY_GUARD_STORAGE;
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

pragma solidity >=0.4.16;

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

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
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

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
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

// File: @openzeppelin/contracts/interfaces/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

pragma solidity >=0.4.16;

// File: @openzeppelin/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/IERC165.sol)

pragma solidity >=0.4.16;

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// File: @openzeppelin/contracts/interfaces/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC165.sol)

pragma solidity >=0.4.16;

// File: @openzeppelin/contracts/interfaces/IERC1363.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1363.sol)

pragma solidity >=0.6.2;

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(
        address from,
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(
        address spender,
        uint256 value
    ) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(
        address spender,
        uint256 value,
        bytes calldata data
    ) external returns (bool);
}

// File: @openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.5.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(
        address spender,
        uint256 currentAllowance,
        uint256 requestedDecrease
    );

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        if (!_safeTransfer(token, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        if (!_safeTransferFrom(token, from, to, value, true)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Variant of {safeTransfer} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal returns (bool) {
        return _safeTransfer(token, to, value, false);
    }

    /**
     * @dev Variant of {safeTransferFrom} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal returns (bool) {
        return _safeTransferFrom(token, from, to, value, false);
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 requestedDecrease
    ) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(
                    spender,
                    currentAllowance,
                    requestedDecrease
                );
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        if (!_safeApprove(token, spender, value, false)) {
            if (!_safeApprove(token, spender, 0, true))
                revert SafeERC20FailedOperation(address(token));
            if (!_safeApprove(token, spender, value, true))
                revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that relies on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(
        IERC1363 token,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that relies on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Oppositely, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(
        IERC1363 token,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity `token.transfer(to, value)` call, relaxing the requirement on the return value: the
     * return value is optional (but if data is returned, it must not be false).
     *
     * @param token The token targeted by the call.
     * @param to The recipient of the tokens
     * @param value The amount of token to transfer
     * @param bubble Behavior switch if the transfer call reverts: bubble the revert reason or return a false boolean.
     */
    function _safeTransfer(
        IERC20 token,
        address to,
        uint256 value,
        bool bubble
    ) private returns (bool success) {
        bytes4 selector = IERC20.transfer.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(to, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
            // if call success and return is true, all is good.
            // otherwise (not success or return is not true), we need to perform further checks
            if iszero(and(success, eq(mload(0x00), 1))) {
                // if the call was a failure and bubble is enabled, bubble the error
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                // if the return value is not true, then the call is only successful if:
                // - the token address has code
                // - the returndata is empty
                success := and(
                    success,
                    and(iszero(returndatasize()), gt(extcodesize(token), 0))
                )
            }
            mstore(0x40, fmp)
        }
    }

    /**
     * @dev Imitates a Solidity `token.transferFrom(from, to, value)` call, relaxing the requirement on the return
     * value: the return value is optional (but if data is returned, it must not be false).
     *
     * @param token The token targeted by the call.
     * @param from The sender of the tokens
     * @param to The recipient of the tokens
     * @param value The amount of token to transfer
     * @param bubble Behavior switch if the transfer call reverts: bubble the revert reason or return a false boolean.
     */
    function _safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value,
        bool bubble
    ) private returns (bool success) {
        bytes4 selector = IERC20.transferFrom.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(from, shr(96, not(0))))
            mstore(0x24, and(to, shr(96, not(0))))
            mstore(0x44, value)
            success := call(gas(), token, 0, 0x00, 0x64, 0x00, 0x20)
            // if call success and return is true, all is good.
            // otherwise (not success or return is not true), we need to perform further checks
            if iszero(and(success, eq(mload(0x00), 1))) {
                // if the call was a failure and bubble is enabled, bubble the error
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                // if the return value is not true, then the call is only successful if:
                // - the token address has code
                // - the returndata is empty
                success := and(
                    success,
                    and(iszero(returndatasize()), gt(extcodesize(token), 0))
                )
            }
            mstore(0x40, fmp)
            mstore(0x60, 0)
        }
    }

    /**
     * @dev Imitates a Solidity `token.approve(spender, value)` call, relaxing the requirement on the return value:
     * the return value is optional (but if data is returned, it must not be false).
     *
     * @param token The token targeted by the call.
     * @param spender The spender of the tokens
     * @param value The amount of token to transfer
     * @param bubble Behavior switch if the transfer call reverts: bubble the revert reason or return a false boolean.
     */
    function _safeApprove(
        IERC20 token,
        address spender,
        uint256 value,
        bool bubble
    ) private returns (bool success) {
        bytes4 selector = IERC20.approve.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(0x00, selector)
            mstore(0x04, and(spender, shr(96, not(0))))
            mstore(0x24, value)
            success := call(gas(), token, 0, 0x00, 0x44, 0x00, 0x20)
            // if call success and return is true, all is good.
            // otherwise (not success or return is not true), we need to perform further checks
            if iszero(and(success, eq(mload(0x00), 1))) {
                // if the call was a failure and bubble is enabled, bubble the error
                if and(iszero(success), bubble) {
                    returndatacopy(fmp, 0x00, returndatasize())
                    revert(fmp, returndatasize())
                }
                // if the return value is not true, then the call is only successful if:
                // - the token address has code
                // - the returndata is empty
                success := and(
                    success,
                    and(iszero(returndatasize()), gt(extcodesize(token), 0))
                )
            }
            mstore(0x40, fmp)
        }
    }
}

// File: NewFlow/POCL.sol

pragma solidity ^0.8.30;

interface IEOAStats {
    function getEOAStats()
        external
        view
        returns (uint256 holders, uint256 totalHeld);
}

interface IMMpool {
    function totalUserStake() external view returns (uint256);
    function withdrawNUSCForPOCL(uint256 amount, address recipient) external;
    function notifyNUSCStaked(uint256 amount) external;
}

interface IPOCLDestination {
    function withdrawNUSCForPOCL(uint256 amount) external;
    function notifyNUSCStaked(uint256 amount) external;
}

interface ITokenPriceOracle {
    /// @dev Returns price and Unix timestamp. Price convention is configured in POCL.
    function getTokenPrice(
        address token
    ) external view returns (uint256 price, uint256 updatedAt);
}

/// @title POCL
/// @notice Protocol-Owned Credit Line funding coordinator.
/// @dev Requires compatible, independently secured MMpool and Vault contracts.
///
/// Delta formula:
/// delta = total EOA-held NUSC
///       + Reserve-held NUSC
///       + 50% of total MMpool user stake
///
/// BorrowFee policy:
/// - Collected NUSC fees are reserved from funding allocations.
/// - When processed, the entire NUSC fee is transferred to BURN_ADDRESS.
/// - The equivalent native NOWA is also transferred to BURN_ADDRESS.
/// - Native NOWA must be funded separately; this contract does not swap tokens.
///
/// Oracle convention for the stated deployment:
/// - price = 0.0004 NUSC per NOWA, scaled by 1e18.
/// - oracleReturnsNowaPerNusc = false.
/// - oraclePriceScale = 1e18.
contract POCL is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant INITIAL_MMPOOL_BPS = 1_000;
    uint256 public constant INITIAL_VAULT_BPS = 9_000;
    uint256 public constant PROPOSAL_LIFETIME = 7 days;
    uint256 public constant MIN_SIGNERS = 3;
    uint256 public constant MAX_SIGNERS = 50;

    address public constant NOWA_NATIVE =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;

    error ZeroAddress();
    error InvalidConfiguration();
    error InvalidSignerSet();
    error NotSigner();
    error InvalidProposal();
    error ProposalExpired();
    error ProposalAlreadyExecuted();
    error AlreadyApproved();
    error ThresholdNotMet();
    error InsufficientPOCLBalance(uint256 required, uint256 available);
    error FeeReserveInvariant(uint256 tokenBalance, uint256 reservedFees);
    error InvalidOraclePrice();
    error StaleOraclePrice();
    error InvalidOracleTimestamp();
    error InsufficientNativeNOWA(uint256 required, uint256 available);
    error NativeTransferFailed();
    error OnlyVault();
    error NoBorrowFees();
    error InvalidPriceScale();
    error UnsupportedTokenBehavior();
    error ArithmeticOverflow();
    error DeltaChangeTooLarge();
    error OnlyMMPool();

    IERC20 public immutable nuscToken;
    IEOAStats public statsContract;
    address public reserveContract;
    IMMpool public mmPool;
    address public bnplVault;
    ITokenPriceOracle public priceOracle;

    uint256 public mmPoolBps = INITIAL_MMPOOL_BPS;
    uint256 public bnplVaultBps = INITIAL_VAULT_BPS;
    uint256 public reconciledDelta;
    uint256 public maxOracleAge;
    uint256 public oraclePriceScale;
    bool public oracleReturnsNowaPerNusc;

    address[] private _signers;
    mapping(address => bool) public isSigner;
    uint256 public signerEpoch;
    uint256 public nextProposalId = 1;

    enum Action {
        SetAllocations,
        AddSigner,
        RemoveSigner,
        SetStatsContract,
        SetReserveContract,
        SetOracle,
        SetMaxOracleAge,
        SetOraclePriceConvention,
        SetMMPool
    }

    struct Proposal {
        Action action;
        address target;
        uint256 value1;
        uint256 value2;
        uint64 createdAt;
        uint64 expiresAt;
        uint32 approvals;
        uint256 epoch;
        bool executed;
        bool cancelled;
    }

    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) public hasApproved;

    uint256 public totalOutstandingAllocation;
    uint256 public outstandingMMpoolAllocation;
    uint256 public outstandingVaultAllocation;
    uint256 public cumulativeAllocatedMMpool;
    uint256 public cumulativeAllocatedVault;
    uint256 public cumulativeRecoveredMMpool;
    uint256 public cumulativeRecoveredVault;
    uint256 public accumulatedMMFeesNUSC;

    /// @notice BorrowFee NUSC collected but not yet dual-burned. Reserved from allocations.
    uint256 public accumulatedBorrowFeesNUSC;
    uint256 public burnedBorrowFeesNUSC;
    uint256 public cumulativeNOWABurned;

    event DeltaCalculated(
        uint256 eoaNUSC,
        uint256 reserveNUSC,
        uint256 halfMMpoolStake,
        uint256 delta
    );
    event Reconciled(
        uint256 previousDelta,
        uint256 currentDelta,
        int256 changeAmount
    );
    event NUSCAllocated(address indexed destination, uint256 amount);
    event NUSCRecovered(address indexed destination, uint256 amount);
    event AllocationBpsChanged(uint256 mmPoolBps, uint256 bnplVaultBps);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        Action action,
        address target,
        uint256 value1,
        uint256 value2,
        uint256 expiresAt
    );
    event ProposalApproved(
        uint256 indexed proposalId,
        address indexed signer,
        uint256 approvals,
        uint256 threshold
    );
    event ProposalExecuted(uint256 indexed proposalId, Action action);
    event ProposalCancelled(uint256 indexed proposalId, address indexed signer);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event StatsContractUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event ReserveContractUpdated(
        address indexed oldAddress,
        address indexed newAddress
    );
    event OracleUpdated(address indexed oldAddress, address indexed newAddress);
    event OraclePolicyUpdated(
        uint256 maxOracleAge,
        uint256 priceScale,
        bool nowaPerNusc
    );
    event BorrowFeeCollected(
        address indexed vault,
        uint256 amount,
        uint256 accumulatedFees
    );
    event BorrowFeeBurned(
        uint256 nuscAmount,
        uint256 nowaAmount,
        uint256 oraclePrice,
        uint256 oracleUpdatedAt,
        uint256 remainingFees
    );
    event NativeNOWAFunded(address indexed sender, uint256 amount);
    event MMPoolUpdated(address indexed oldAddress, address indexed newAddress);

    modifier onlySigner() {
        if (!isSigner[msg.sender]) revert NotSigner();
        _;
    }

    /// @param _nusc NUSC ERC-20 contract.
    /// @param _stats EOA statistics contract.
    /// @param _reserve Address holding Reserve NUSC.
    /// @param _mmPool MMpool contract.
    /// @param _bnplVault BNPL Vault contract.
    /// @param _oracle Price oracle returning getTokenPrice(address).
    /// @param signers Four or five distinct initial signers.
    /// @param _maxOracleAge Maximum accepted oracle-data age in seconds.
    /// @param _priceScale Oracle quote precision; use 1e18 for the stated quote.
    /// @param _oracleReturnsNowaPerNusc False for NUSC per NOWA.
    constructor(
        address _nusc,
        address _stats,
        address _reserve,
        address _mmPool,
        address _bnplVault,
        address _oracle,
        address[] memory signers,
        uint256 _maxOracleAge,
        uint256 _priceScale,
        bool _oracleReturnsNowaPerNusc
    ) Ownable(msg.sender) {
        if (
            _nusc == address(0) ||
            _stats == address(0) ||
            _reserve == address(0) ||
            _mmPool == address(0) ||
            _bnplVault == address(0) ||
            _oracle == address(0)
        ) {
            revert ZeroAddress();
        }
        if (
            _nusc.code.length == 0 ||
            _stats.code.length == 0 ||
            _mmPool.code.length == 0 ||
            _bnplVault.code.length == 0 ||
            _oracle.code.length == 0
        ) {
            revert InvalidConfiguration();
        }
        if (
            signers.length < MIN_SIGNERS ||
            signers.length > MAX_SIGNERS ||
            _maxOracleAge == 0 ||
            _priceScale == 0
        ) {
            revert InvalidConfiguration();
        }

        nuscToken = IERC20(_nusc);
        statsContract = IEOAStats(_stats);
        reserveContract = _reserve;
        mmPool = IMMpool(_mmPool);
        bnplVault = _bnplVault;
        priceOracle = ITokenPriceOracle(_oracle);
        maxOracleAge = _maxOracleAge;
        oraclePriceScale = _priceScale;
        oracleReturnsNowaPerNusc = _oracleReturnsNowaPerNusc;

        for (uint256 i; i < signers.length; ++i) {
            address signer = signers[i];
            if (signer == address(0) || isSigner[signer])
                revert InvalidSignerSet();
            isSigner[signer] = true;
            _signers.push(signer);
            emit SignerAdded(signer);
        }
    }

    receive() external payable {
        emit NativeNOWAFunded(msg.sender, msg.value);
    }

    function threshold() public view returns (uint256) {
        return (_signers.length * 2 + 2) / 3;
    }

    function getSigners() external view returns (address[] memory) {
        return _signers;
    }

    /// @dev Checked multiplication followed by division. Unlike full-precision mulDiv,
    /// this intentionally reverts if the intermediate product exceeds uint256.
    function _checkedMulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256) {
        if (denominator == 0) revert InvalidConfiguration();
        if (b != 0 && a > type(uint256).max / b) revert ArithmeticOverflow();
        return (a * b) / denominator;
    }

    function _calculateDelta()
        internal
        view
        returns (
            uint256 delta,
            uint256 eoaNUSC,
            uint256 reserveNUSC,
            uint256 halfStake
        )
    {
        (, eoaNUSC) = statsContract.getEOAStats();
        reserveNUSC = nuscToken.balanceOf(reserveContract);
        halfStake = mmPool.totalUserStake() / 2;
        delta = eoaNUSC + reserveNUSC + halfStake;
    }

    function calculateDelta() external view returns (uint256 delta) {
        (delta, , , ) = _calculateDelta();
    }

    function reportDelta() external returns (uint256 delta) {
        uint256 eoaNUSC;
        uint256 reserveNUSC;
        uint256 halfStake;
        (delta, eoaNUSC, reserveNUSC, halfStake) = _calculateDelta();
        emit DeltaCalculated(eoaNUSC, reserveNUSC, halfStake, delta);
    }

    /// @notice Permissionlessly reconcile allocations to the current funding target.
    function syncAndReconcile() external nonReentrant {
        (
            uint256 currentDelta,
            uint256 eoaNUSC,
            uint256 reserveNUSC,
            uint256 halfStake
        ) = _calculateDelta();
        emit DeltaCalculated(eoaNUSC, reserveNUSC, halfStake, currentDelta);

        uint256 previousDelta = reconciledDelta;
        uint256 outstanding = totalOutstandingAllocation;

        if (
            outstanding !=
                outstandingMMpoolAllocation + outstandingVaultAllocation ||
            outstanding != previousDelta
        ) revert InvalidConfiguration();

        if (currentDelta > outstanding) {
            _allocateIncrease(currentDelta - outstanding);
        } else if (currentDelta < outstanding) {
            _recoverDecrease(outstanding - currentDelta);
        }

        reconciledDelta = currentDelta;
        uint256 difference = currentDelta >= previousDelta
            ? currentDelta - previousDelta
            : previousDelta - currentDelta;
        if (difference > uint256(type(int256).max))
            revert DeltaChangeTooLarge();
        int256 signedChange = currentDelta >= previousDelta
            ? int256(difference)
            : -int256(difference);
        emit Reconciled(previousDelta, currentDelta, signedChange);
    }

    function _allocateIncrease(uint256 increase) internal {
        uint256 mmAmount = _checkedMulDiv(increase, mmPoolBps, BPS_DENOMINATOR);
        uint256 vaultAmount = increase - mmAmount;

        uint256 tokenBalance = nuscToken.balanceOf(address(this));
        uint256 reservedFees = accumulatedBorrowFeesNUSC;
        if (tokenBalance < reservedFees)
            revert FeeReserveInvariant(tokenBalance, reservedFees);

        uint256 available = tokenBalance - reservedFees;
        if (available < increase)
            revert InsufficientPOCLBalance(increase, available);

        totalOutstandingAllocation += increase;
        outstandingMMpoolAllocation += mmAmount;
        outstandingVaultAllocation += vaultAmount;
        cumulativeAllocatedMMpool += mmAmount;
        cumulativeAllocatedVault += vaultAmount;

        if (mmAmount != 0) {
            nuscToken.safeTransfer(address(mmPool), mmAmount);
            // Notify MMpool after receiving NUSC.
            mmPool.notifyNUSCStaked(mmAmount);
            emit NUSCAllocated(address(mmPool), mmAmount);
        }
        if (vaultAmount != 0) {
            nuscToken.safeTransfer(bnplVault, vaultAmount);

            // Notify BNPL Vault after receiving NUSC.
            IPOCLDestination(bnplVault).notifyNUSCStaked(vaultAmount);
            emit NUSCAllocated(bnplVault, vaultAmount);
        }
    }

    function _recoverDecrease(uint256 decrease) internal {
        uint256 outstanding = totalOutstandingAllocation;
        uint256 mmTake;
        uint256 vaultTake;

        if (decrease == outstanding) {
            mmTake = outstandingMMpoolAllocation;
            vaultTake = outstandingVaultAllocation;
        } else {
            mmTake = _checkedMulDiv(
                decrease,
                outstandingMMpoolAllocation,
                outstanding
            );
            vaultTake = decrease - mmTake;
            if (
                mmTake > outstandingMMpoolAllocation ||
                vaultTake > outstandingVaultAllocation
            ) {
                revert InvalidConfiguration();
            }
        }

        totalOutstandingAllocation -= decrease;
        outstandingMMpoolAllocation -= mmTake;
        outstandingVaultAllocation -= vaultTake;
        cumulativeRecoveredMMpool += mmTake;
        cumulativeRecoveredVault += vaultTake;

        if (mmTake != 0) {
            mmPool.withdrawNUSCForPOCL(mmTake, address(this));
            emit NUSCRecovered(address(mmPool), mmTake);
        }
        if (vaultTake != 0) {
            IPOCLDestination(bnplVault).withdrawNUSCForPOCL(vaultTake);
            emit NUSCRecovered(bnplVault, vaultTake);
        }
    }

    function propose(
        Action action,
        address target,
        uint256 value1,
        uint256 value2
    ) external onlySigner returns (uint256 id) {
        if (action == Action.RemoveSigner && target == msg.sender)
            revert InvalidProposal();
        _validateProposal(action, target, value1, value2);

        id = nextProposalId++;
        uint64 expiry = uint64(block.timestamp + PROPOSAL_LIFETIME);
        Proposal storage p = _proposals[id];
        p.action = action;
        p.target = target;
        p.value1 = value1;
        p.value2 = value2;
        p.createdAt = uint64(block.timestamp);
        p.expiresAt = expiry;
        p.epoch = signerEpoch;
        p.approvals = 1;
        hasApproved[id][msg.sender] = true;

        emit ProposalCreated(
            id,
            msg.sender,
            action,
            target,
            value1,
            value2,
            expiry
        );
        emit ProposalApproved(id, msg.sender, 1, threshold());
    }

    function approveProposal(uint256 id) external onlySigner {
        Proposal storage p = _proposals[id];
        if (
            p.createdAt == 0 ||
            p.cancelled ||
            p.executed ||
            p.epoch != signerEpoch
        ) revert InvalidProposal();
        if (block.timestamp > p.expiresAt) revert ProposalExpired();
        if (p.action == Action.RemoveSigner && msg.sender == p.target)
            revert InvalidProposal();
        if (hasApproved[id][msg.sender]) revert AlreadyApproved();

        hasApproved[id][msg.sender] = true;
        ++p.approvals;
        emit ProposalApproved(id, msg.sender, p.approvals, threshold());
    }

    function executeProposal(uint256 id) external nonReentrant {
        Proposal storage p = _proposals[id];
        if (p.createdAt == 0 || p.cancelled || p.epoch != signerEpoch)
            revert InvalidProposal();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > p.expiresAt) revert ProposalExpired();
        if (p.approvals < threshold()) revert ThresholdNotMet();

        p.executed = true;
        Action action = p.action;

        if (action == Action.SetAllocations) {
            mmPoolBps = p.value1;
            bnplVaultBps = p.value2;
            emit AllocationBpsChanged(p.value1, p.value2);
        } else if (action == Action.AddSigner) {
            _addSigner(p.target);
        } else if (action == Action.RemoveSigner) {
            _removeSigner(p.target);
        } else if (action == Action.SetStatsContract) {
            address oldAddress = address(statsContract);
            statsContract = IEOAStats(p.target);
            emit StatsContractUpdated(oldAddress, p.target);
        } else if (action == Action.SetReserveContract) {
            address oldAddress = reserveContract;
            reserveContract = p.target;
            emit ReserveContractUpdated(oldAddress, p.target);
        } else if (action == Action.SetOracle) {
            address oldAddress = address(priceOracle);
            priceOracle = ITokenPriceOracle(p.target);
            emit OracleUpdated(oldAddress, p.target);
        } else if (action == Action.SetMaxOracleAge) {
            maxOracleAge = p.value1;
            emit OraclePolicyUpdated(
                maxOracleAge,
                oraclePriceScale,
                oracleReturnsNowaPerNusc
            );
        } else if (action == Action.SetOraclePriceConvention) {
            oraclePriceScale = p.value1;
            oracleReturnsNowaPerNusc = p.value2 == 1;
            emit OraclePolicyUpdated(
                maxOracleAge,
                oraclePriceScale,
                oracleReturnsNowaPerNusc
            );
        } else if (action == Action.SetMMPool) {
            address oldAddress = address(mmPool);
            mmPool = IMMpool(p.target);

            emit MMPoolUpdated(oldAddress, p.target);
        } else {
            revert InvalidProposal();
        }

        emit ProposalExecuted(id, action);
    }

    function cancelProposal(uint256 id) external onlySigner {
        Proposal storage p = _proposals[id];
        if (
            p.createdAt == 0 ||
            p.executed ||
            p.cancelled ||
            p.epoch != signerEpoch
        ) revert InvalidProposal();
        p.cancelled = true;
        emit ProposalCancelled(id, msg.sender);
    }

    function _validateProposal(
        Action action,
        address target,
        uint256 value1,
        uint256 value2
    ) internal view {
        if (action == Action.SetAllocations) {
            if (
                value1 == 0 ||
                value2 == 0 ||
                value1 > BPS_DENOMINATOR ||
                value2 > BPS_DENOMINATOR ||
                value1 + value2 != BPS_DENOMINATOR
            ) {
                revert InvalidConfiguration();
            }
        } else if (action == Action.AddSigner) {
            if (
                target == address(0) ||
                isSigner[target] ||
                _signers.length >= MAX_SIGNERS
            ) revert InvalidSignerSet();
        } else if (action == Action.RemoveSigner) {
            if (!isSigner[target] || _signers.length <= MIN_SIGNERS)
                revert InvalidSignerSet();
        } else if (
            action == Action.SetStatsContract || action == Action.SetOracle
        ) {
            if (target == address(0) || target.code.length == 0)
                revert InvalidConfiguration();
        } else if (action == Action.SetReserveContract) {
            if (target == address(0)) revert ZeroAddress();
        } else if (action == Action.SetMaxOracleAge) {
            if (value1 == 0) revert InvalidConfiguration();
        } else if (action == Action.SetOraclePriceConvention) {
            if (value1 == 0 || value2 > 1) revert InvalidPriceScale();
        } else if (action == Action.SetMMPool) {
            if (target == address(0) || target.code.length == 0) {
                revert InvalidConfiguration();
            }
        }
    }

    function _addSigner(address signer) internal {
        if (
            signer == address(0) ||
            isSigner[signer] ||
            _signers.length >= MAX_SIGNERS
        ) revert InvalidSignerSet();
        isSigner[signer] = true;
        _signers.push(signer);
        ++signerEpoch;
        emit SignerAdded(signer);
    }

    function _removeSigner(address signer) internal {
        if (!isSigner[signer] || _signers.length <= MIN_SIGNERS)
            revert InvalidSignerSet();
        isSigner[signer] = false;

        for (uint256 i; i < _signers.length; ++i) {
            if (_signers[i] == signer) {
                _signers[i] = _signers[_signers.length - 1];
                _signers.pop();
                break;
            }
        }

        ++signerEpoch;
        emit SignerRemoved(signer);
    }

    /// @notice Pull BorrowFee NUSC from the configured Vault and record it once.
    /// @dev Vault must approve this contract for amount before calling.
    function collectBorrowFee(uint256 amount) external nonReentrant {
        if (msg.sender != bnplVault) revert OnlyVault();
        if (amount == 0) revert InvalidConfiguration();

        nuscToken.safeTransferFrom(msg.sender, address(this), amount);

        accumulatedBorrowFeesNUSC += amount;
        emit BorrowFeeCollected(msg.sender, amount, accumulatedBorrowFeesNUSC);
    }

    function collectMmFee(uint256 amount) external nonReentrant {
        if (msg.sender != address(mmPool)) revert OnlyMMPool();
        if (amount == 0) revert InvalidConfiguration();

        nuscToken.safeTransferFrom(msg.sender, address(this), amount);

        accumulatedMMFeesNUSC += amount;
        emit BorrowFeeCollected(msg.sender, amount, accumulatedBorrowFeesNUSC);
    }

    /// @notice Burn all pending BorrowFee NUSC and equivalent native NOWA.
    ///      Native NOWA must be funded separately; no swap is performed.
    function burnNOWAForCollectedFees() external nonReentrant {
        uint256 fees = accumulatedBorrowFeesNUSC;
        if (fees == 0) revert NoBorrowFees();

        (uint256 price, uint256 updatedAt) = priceOracle.getTokenPrice(
            NOWA_NATIVE
        );
        if (price == 0) revert InvalidOraclePrice();
        if (updatedAt == 0 || updatedAt > block.timestamp)
            revert InvalidOracleTimestamp();
        if (block.timestamp - updatedAt > maxOracleAge)
            revert StaleOraclePrice();

        uint256 nowaAmount;
        if (oracleReturnsNowaPerNusc) {
            nowaAmount = _checkedMulDiv(fees, price, oraclePriceScale);
        } else {
            nowaAmount = _checkedMulDiv(fees, oraclePriceScale, price);
        }
        if (nowaAmount == 0) revert InvalidOraclePrice();

        uint256 nativeBalance = address(this).balance;
        if (nativeBalance < nowaAmount)
            revert InsufficientNativeNOWA(nowaAmount, nativeBalance);

        uint256 tokenBalance = nuscToken.balanceOf(address(this));
        if (tokenBalance < fees) revert FeeReserveInvariant(tokenBalance, fees);

        // Effects first. Any failed transfer reverts all state changes atomically.
        accumulatedBorrowFeesNUSC = 0;
        burnedBorrowFeesNUSC += fees;
        cumulativeNOWABurned += nowaAmount;

        nuscToken.safeTransfer(BURN_ADDRESS, fees);

        (bool success, ) = payable(BURN_ADDRESS).call{value: nowaAmount}("");
        if (!success) revert NativeTransferFailed();

        emit BorrowFeeBurned(
            fees,
            nowaAmount,
            price,
            updatedAt,
            accumulatedBorrowFeesNUSC
        );
    }

    function getProposal(
        uint256 id
    )
        external
        view
        returns (
            Action action,
            address target,
            uint256 value1,
            uint256 value2,
            uint64 createdAt,
            uint64 expiresAt,
            uint32 approvals,
            uint256 epoch,
            bool executed,
            bool cancelled
        )
    {
        Proposal storage p = _proposals[id];
        return (
            p.action,
            p.target,
            p.value1,
            p.value2,
            p.createdAt,
            p.expiresAt,
            p.approvals,
            p.epoch,
            p.executed,
            p.cancelled
        );
    }
}
