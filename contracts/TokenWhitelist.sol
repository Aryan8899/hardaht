// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenWhitelist is Ownable {

    // ================= STORAGE =================

    mapping(address => bool) private whitelistedTokens;
    mapping(address => bool) public controllers;

    // ================= EVENTS =================

    event TokenWhitelisted(address indexed token);
    event TokenUnlisted(address indexed token);
    event ControllerUpdated(address indexed controller, bool allowed);

    // ================= CONSTRUCTOR =================

    constructor() Ownable(msg.sender) {}

    // ================= MODIFIERS =================

    modifier onlyOwnerOrController() {
        require(owner() == msg.sender || controllers[msg.sender], "Not allowed");
        _;
    }

    // ================= ADMIN =================

    function setController(address controller, bool allowed) external onlyOwner {
        require(controller != address(0), "zero controller");
        controllers[controller] = allowed;
        emit ControllerUpdated(controller, allowed);
    }

    function whitelistToken(address token) external onlyOwnerOrController {
        require(token != address(0), "zero token");
        require(!whitelistedTokens[token], "already whitelisted");

        whitelistedTokens[token] = true;

        emit TokenWhitelisted(token);
    }

    function unlistToken(address token) external onlyOwnerOrController {
        require(whitelistedTokens[token], "not listed");

        delete whitelistedTokens[token];

        emit TokenUnlisted(token);
    }

    /// @dev Batch whitelist (production must-have)
    function whitelistTokens(address[] calldata tokens) external onlyOwnerOrController {
        uint256 len = tokens.length;
        for (uint256 i; i < len; ) {
            address token = tokens[i];
            require(token != address(0), "zero token");

            if (!whitelistedTokens[token]) {
                whitelistedTokens[token] = true;
                emit TokenWhitelisted(token);
            }

            unchecked { ++i; }
        }
    }

    // ================= CORE VALIDATION =================

    /// @notice Use this inside BNPL contract before allowing trade
    function validateTradeToken(address token) external view {
        require(whitelistedTokens[token], "TOKEN_NOT_WHITELISTED");
    }

    /// @notice Validate both tokens in a pair (recommended)
    function validateTradePair(address token0, address token1) external view {
        require(whitelistedTokens[token0], "TOKEN0_NOT_ALLOWED");
        require(whitelistedTokens[token1], "TOKEN1_NOT_ALLOWED");
    }


    // ================= VIEW =================

    function isTokenWhitelisted(address token) external view returns (bool) {
        return whitelistedTokens[token];
    }
}