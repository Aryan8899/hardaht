// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Aryu.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AryuVaultFactory {
    address public owner;

    mapping(address => mapping(address => address)) public getVault;
    address[] public allVaults;
    mapping(address => bool) public isVault;
   mapping(address => bool) public whitelisted;
address[] public whitelistedList;  
    uint256 public minStakeAmount;

    event VaultCreated(
        address indexed token0,
        address indexed token1,
        address vault
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint _minStakeAmount) {
        owner = msg.sender;
        minStakeAmount = _minStakeAmount;
    }

    function createVault(
        address tokenA,
        address tokenB,
        address[] calldata operators
    ) external onlyOwner returns (address vault) {
        require(tokenA != tokenB, "Identical tokens");

        (address token0, address token1) = sortTokens(tokenA, tokenB);
        require(getVault[token0][token1] == address(0), "Vault exists");

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        vault = address(new Aryu{salt: salt}(minStakeAmount)); // ✅ constructor me jaega

        Aryu(vault).initialize(token0, token1, operators); // 👈 pass karo
        getVault[token0][token1] = vault;
        getVault[token1][token0] = vault;

        allVaults.push(vault);
        isVault[vault] = true;

        emit VaultCreated(token0, token1, vault);
    }

    function sortTokens(
        address tokenA,
        address tokenB
    ) public pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }

    function allVaultsLength() external view returns (uint256) {
        return allVaults.length;
    }

    // ----------- Predict Address (CREATE2) -----------

    function getVaultAddress(
        address tokenA,
        address tokenB
    ) external view returns (address predicted) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        bytes memory bytecode = abi.encodePacked(
            type(Aryu).creationCode,
            abi.encode(minStakeAmount)
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );

        predicted = address(uint160(uint256(hash)));
    }

    // Owner add/remove kar sake
   function addWhitelist(address[] calldata _addrs) external onlyOwner {
    for (uint256 i = 0; i < _addrs.length; i++) {
        require(_addrs[i] != address(0), "Invalid address");
        if (!whitelisted[_addrs[i]]) {
            whitelisted[_addrs[i]] = true;
            whitelistedList.push(_addrs[i]);
        }
    }
}

function removeWhitelist(address _addr) external onlyOwner {
    require(whitelisted[_addr], "Not whitelisted");
    whitelisted[_addr] = false;

    // Array se bhi hatao
    for (uint256 i = 0; i < whitelistedList.length; i++) {
        if (whitelistedList[i] == _addr) {
            whitelistedList[i] = whitelistedList[whitelistedList.length - 1];
            whitelistedList.pop();
            break;
        }
    }
}

function getWhitelistedList() external view returns (address[] memory) {
    return whitelistedList;
}
}
