// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {ERC1271Delegated} from "../exts/ERC1271Delegated.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";
import {EInsufficientBalance} from "../errors/InsufficientBalance.sol";

/**
 * @title OrderDelegate
 * @notice Contract skeleton for delegated order signing and execution
 */
contract OrderDelegate is
    ERC1271Delegated,
    AccessManaged,
    Pausable,
    ReentrancyGuardTransient,
    EInvalidAmount,
    EInsufficientBalance
{
    using SafeERC20 for IERC20;

    /// @notice Beneficiary address that receives minted/received assets
    address public immutable beneficiary;
    /// @notice Asset token (e.g. apxUSD)
    IERC20 public immutable asset;

    /**
     * @notice Initializes the order delegate
     * @param _authority Address of the AccessManager contract
     * @param _beneficiary Beneficiary that receives assets
     * @param _signingDelegate Address that may sign on behalf of this contract
     * @param _asset Asset token
     */
    constructor(address _authority, address _beneficiary, address _signingDelegate, address _asset)
        AccessManaged(_authority)
        ERC1271Delegated(_signingDelegate)
    {
        if (_authority == address(0)) revert InvalidAddress("authority");
        if (_beneficiary == address(0)) revert InvalidAddress("beneficiary");
        if (_signingDelegate == address(0)) revert InvalidAddress("signingDelegate");
        if (_asset == address(0)) revert InvalidAddress("asset");

        beneficiary = _beneficiary;
        asset = IERC20(_asset);
    }

    /// @notice ERC-1271: when paused, reverts so no new mints to this beneficiary
    function isValidSignature(bytes32 hash, bytes calldata signature)
        public
        view
        override
        whenNotPaused
        returns (bytes4 magicValue)
    {
        return super.isValidSignature(hash, signature);
    }

    /// @notice Pauses the contract (isValidSignature will revert when paused). No unpause.
    function pause() external restricted {
        _pause();
    }

    /// @notice Transfers the configured asset to the beneficiary (convenience for primary mint token)
    /// @param amount Amount to transfer
    function transfer(uint256 amount) external restricted {
        transferToken(address(asset), amount);
    }

    /// @notice Transfers an ERC20 from this contract to the beneficiary
    /// @param token Token address
    /// @param amount Amount to transfer
    function transferToken(address token, uint256 amount) public restricted nonReentrant {
        if (amount == 0) revert InvalidAmount("amount", amount);
        if (token == address(0)) revert InvalidAddress("token");

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance(address(this), balance, amount);

        IERC20(token).safeTransfer(beneficiary, amount);
    }
}
