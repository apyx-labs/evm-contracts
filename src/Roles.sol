// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    IAccessManager
} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {ApxUSD} from "./ApxUSD.sol";
import {ApyUSD} from "./ApyUSD.sol";
import {IMinterV0} from "./interfaces/IMinterV0.sol";
import {IVesting} from "./interfaces/IVesting.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";

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

    /**
     * @notice Assigns admin function selectors for ApxUSD contract
     * @param accessManager The AccessManager contract
     * @param apxUSD The ApxUSD contract address
     */
    function assignAdminTargetsFor(
        IAccessManager accessManager,
        ApxUSD apxUSD
    ) internal {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = ApxUSD.pause.selector;
        selectors[1] = ApxUSD.unpause.selector;
        selectors[2] = ApxUSD.setSupplyCap.selector;
        selectors[3] = ApxUSD.freeze.selector;
        selectors[4] = ApxUSD.unfreeze.selector;
        accessManager.setTargetFunctionRole(
            address(apxUSD),
            selectors,
            ADMIN_ROLE
        );
    }

    /**
     * @notice Assigns admin function selectors for MinterV0 contract
     * @param accessManager The AccessManager contract
     * @param mintingContract The Minting contract address
     */
    function assignAdminTargetsFor(
        IAccessManager accessManager,
        IMinterV0 mintingContract
    ) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IMinterV0.setMaxMintAmount.selector;
        selectors[1] = IMinterV0.setRateLimit.selector;
        accessManager.setTargetFunctionRole(
            address(mintingContract),
            selectors,
            ADMIN_ROLE
        );
    }

    /**
     * @notice Assigns admin function selectors for ApyUSD contract
     * @param accessManager The AccessManager contract
     * @param apyUSD The ApyUSD contract address
     */
    function assignAdminTargetsFor(
        IAccessManager accessManager,
        ApyUSD apyUSD
    ) internal {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ApyUSD.setUnlockingDelay.selector;
        selectors[1] = ApyUSD.pause.selector;
        selectors[2] = ApyUSD.unpause.selector;
        selectors[3] = ApyUSD.setSilo.selector;
        selectors[4] = ApyUSD.setVesting.selector;
        selectors[5] = ApyUSD.freeze.selector;
        selectors[6] = ApyUSD.unfreeze.selector;
        accessManager.setTargetFunctionRole(
            address(apyUSD),
            selectors,
            ADMIN_ROLE
        );
    }

    /**
     * @notice Assigns admin function selectors for Vesting contract
     * @param accessManager The AccessManager contract
     * @param vestingContract The Vesting contract address
     */
    function assignAdminTargetsFor(
        IAccessManager accessManager,
        IVesting vestingContract
    ) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IVesting.setVestingPeriod.selector;
        selectors[1] = IVesting.setBeneficiary.selector;
        accessManager.setTargetFunctionRole(
            address(vestingContract),
            selectors,
            ADMIN_ROLE
        );
    }

    /**
     * @notice Assigns admin function selectors for AddressList (DenyList) contract
     * @param accessManager The AccessManager contract
     * @param denyList The AddressList contract address
     */
    function assignAdminTargetsFor(
        IAccessManager accessManager,
        IAddressList denyList
    ) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IAddressList.add.selector;
        selectors[1] = IAddressList.remove.selector;
        accessManager.setTargetFunctionRole(
            address(denyList),
            selectors,
            ADMIN_ROLE
        );
    }

    /**
     * @notice Assigns minter function selector for MinterV0 contract
     * @param accessManager The AccessManager contract
     * @param minterContract The MinterV0 contract address
     */
    function assignMinterTargetsFor(
        IAccessManager accessManager,
        IMinterV0 minterContract
    ) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IMinterV0.requestMint.selector;
        selectors[1] = IMinterV0.executeMint.selector;
        accessManager.setTargetFunctionRole(
            address(minterContract),
            selectors,
            MINTER_ROLE
        );
    }

    /**
     * @notice Assigns mint guard function selector for MinterV0 contract
     * @param accessManager The AccessManager contract
     * @param minterContract The MinterV0 contract address
     */
    function assignMintGuardTargetsFor(
        IAccessManager accessManager,
        IMinterV0 minterContract
    ) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IMinterV0.cancelMint.selector;
        accessManager.setTargetFunctionRole(
            address(minterContract),
            selectors,
            MINT_GUARD_ROLE
        );
    }

    /**
     * @notice Assigns minting contract function selector for ApxUSD contract
     * @param accessManager The AccessManager contract
     * @param apxUSD The ApxUSD contract address
     */
    function assignMintingContractTargetsFor(
        IAccessManager accessManager,
        ApxUSD apxUSD
    ) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ApxUSD.mint.selector;
        accessManager.setTargetFunctionRole(
            address(apxUSD),
            selectors,
            MINT_STRAT_ROLE
        );
    }

    /**
     * @notice Assigns yield distributor function selector for Vesting contract
     * @param accessManager The AccessManager contract
     * @param vestingContract The Vesting contract address
     */
    function assignYieldDistributorTargetsFor(
        IAccessManager accessManager,
        IVesting vestingContract
    ) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IVesting.depositYield.selector;
        accessManager.setTargetFunctionRole(
            address(vestingContract),
            selectors,
            YIELD_DISTRIBUTOR_ROLE
        );
    }
}
