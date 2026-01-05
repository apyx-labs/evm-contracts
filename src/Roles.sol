// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title Roles
 * @notice Centralized role definitions for AccessManager-based access control
 * @dev These role IDs are used across the PrefUSD ecosystem for consistent access management
 */
library Roles {
    /// @notice Built-in OpenZeppelin admin role - controls all other roles and critical functions
    uint64 public constant ADMIN_ROLE = 0;

    /// @notice Minting strategy role - granted to minting contracts (e.g., MinterV0)
    /// @dev Can call PrefUSD.mint() with no execution delay
    uint64 public constant MINT_STRAT_ROLE = 1;

    /// @notice Individual minter role - granted to authorized minter addresses
    /// @dev Can call MinterV0.requestMint() and executeMint() with configured delays
    uint64 public constant MINTER_ROLE = 2;

    /// @notice Mint guardian role - granted to compliance guardians
    /// @dev Can call MinterV0.cancelMint() to stop non-compliant mint operations
    uint64 public constant MINT_GUARD_ROLE = 3;

    /// @notice Yield distributor role - granted to addresses that can deposit yield
    /// @dev Can call Vesting.depositYield() to add yield for vesting
    uint64 public constant YIELD_DISTRIBUTOR_ROLE = 6;
}
