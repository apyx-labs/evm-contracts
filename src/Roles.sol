// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "./ApxUSD.sol";
import {ApyUSD} from "./ApyUSD.sol";
import {IMinterV0} from "./interfaces/IMinterV0.sol";
import {IVesting} from "./interfaces/IVesting.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {IYieldDistributor} from "./interfaces/IYieldDistributor.sol";

/**
 * @title Roles
 * @notice Centralized role definitions for AccessManager-based access control
 * @dev These role IDs are used across the Apyx ecosystem of contracts for consistent access management
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

    /// @notice Yield operator role - granted to addresses that can trigger yield deposits
    /// @dev Can call YieldDistributor.depositYield() to deposit yield to vesting
    uint64 public constant ROLE_YIELD_OPERATOR = 7;

    // ========================================
    // Extension Functions for AccessManager
    // ========================================

    /**
     * @notice Sets the admin role for all roles (extension function)
     * @param self The AccessManager contract
     */
    function setRoleAdmins(AccessManager self) internal {
        self.setRoleAdmin(MINT_STRAT_ROLE, ADMIN_ROLE);
        self.setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        self.setRoleAdmin(MINT_GUARD_ROLE, ADMIN_ROLE);
        self.setRoleAdmin(YIELD_DISTRIBUTOR_ROLE, ADMIN_ROLE);
        self.setRoleAdmin(ROLE_YIELD_OPERATOR, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for ApxUSD contract (extension function)
     * @param self The AccessManager contract
     * @param apxUSD The ApxUSD contract
     */
    function assignAdminTargetsFor(AccessManager self, ApxUSD apxUSD) internal {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = ApxUSD.pause.selector;
        selectors[1] = ApxUSD.unpause.selector;
        selectors[2] = ApxUSD.setSupplyCap.selector;
        selectors[3] = ApxUSD.freeze.selector;
        selectors[4] = ApxUSD.unfreeze.selector;
        self.setTargetFunctionRole(address(apxUSD), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for MinterV0 contract (extension function)
     * @param self The AccessManager contract
     * @param minterContract The MinterV0 contract
     */
    function assignAdminTargetsFor(AccessManager self, IMinterV0 minterContract) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IMinterV0.setMaxMintAmount.selector;
        selectors[1] = IMinterV0.setRateLimit.selector;
        self.setTargetFunctionRole(address(minterContract), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for ApyUSD contract (extension function)
     * @param self The AccessManager contract
     * @param apyUSD The ApyUSD contract
     */
    function assignAdminTargetsFor(AccessManager self, ApyUSD apyUSD) internal {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ApyUSD.setUnlockingDelay.selector;
        selectors[1] = ApyUSD.pause.selector;
        selectors[2] = ApyUSD.unpause.selector;
        selectors[3] = ApyUSD.setSilo.selector;
        selectors[4] = ApyUSD.setVesting.selector;
        selectors[5] = ApyUSD.freeze.selector;
        selectors[6] = ApyUSD.unfreeze.selector;
        self.setTargetFunctionRole(address(apyUSD), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for Vesting contract (extension function)
     * @param self The AccessManager contract
     * @param vestingContract The Vesting contract
     */
    function assignAdminTargetsFor(AccessManager self, IVesting vestingContract) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IVesting.setVestingPeriod.selector;
        selectors[1] = IVesting.setBeneficiary.selector;
        self.setTargetFunctionRole(address(vestingContract), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for AddressList contract (extension function)
     * @param self The AccessManager contract
     * @param denyList The AddressList contract
     */
    function assignAdminTargetsFor(AccessManager self, IAddressList denyList) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IAddressList.add.selector;
        selectors[1] = IAddressList.remove.selector;
        self.setTargetFunctionRole(address(denyList), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns ADMIN_ROLE function selectors for YieldDistributor contract (extension function)
     * @param self The AccessManager contract
     * @param yieldDistributor The YieldDistributor contract
     */
    function assignAdminTargetsFor(AccessManager self, IYieldDistributor yieldDistributor) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IYieldDistributor.setVesting.selector;
        self.setTargetFunctionRole(address(yieldDistributor), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns MINTER_ROLE function selectors for MinterV0 contract (extension function)
     * @param self The AccessManager contract
     * @param minterContract The MinterV0 contract
     */
    function assignMinterTargetsFor(AccessManager self, IMinterV0 minterContract) internal {
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = IMinterV0.requestMint.selector;
        selectors[1] = IMinterV0.executeMint.selector;
        selectors[2] = IMinterV0.cleanMintHistory.selector;
        self.setTargetFunctionRole(address(minterContract), selectors, MINTER_ROLE);
    }

    /**
     * @notice Assigns mint guard function selectors for MinterV0 contract (extension function)
     * @param self The AccessManager contract
     * @param minterContract The MinterV0 contract
     */
    function assignMintGuardTargetsFor(AccessManager self, IMinterV0 minterContract) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IMinterV0.cancelMint.selector;
        self.setTargetFunctionRole(address(minterContract), selectors, MINT_GUARD_ROLE);
    }

    /**
     * @notice Assigns minting contract function selectors for ApxUSD contract (extension function)
     * @param self The AccessManager contract
     * @param apxUSD The ApxUSD contract
     */
    function assignMintingContractTargetsFor(AccessManager self, ApxUSD apxUSD) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ApxUSD.mint.selector;
        self.setTargetFunctionRole(address(apxUSD), selectors, MINT_STRAT_ROLE);
    }

    /**
     * @notice Assigns yield distributor function selectors for Vesting contract (extension function)
     * @param self The AccessManager contract
     * @param vestingContract The Vesting contract
     */
    function assignYieldDistributorTargetsFor(AccessManager self, IVesting vestingContract) internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IVesting.depositYield.selector;
        self.setTargetFunctionRole(address(vestingContract), selectors, YIELD_DISTRIBUTOR_ROLE);
    }

    /**
     * @notice Assigns ROLE_YIELD_OPERATOR function selectors for YieldDistributor contract (extension function)
     * @param self The AccessManager contract
     * @param yieldDistributor The YieldDistributor contract
     */
    function assignYieldOperatorTargetsFor(AccessManager self, IYieldDistributor yieldDistributor) internal {
        bytes4[] memory operatorSelectors = new bytes4[](1);
        operatorSelectors[0] = IYieldDistributor.depositYield.selector;
        self.setTargetFunctionRole(address(yieldDistributor), operatorSelectors, ROLE_YIELD_OPERATOR);
    }
}
