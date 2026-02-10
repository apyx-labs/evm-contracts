// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "./ApxUSD.sol";
import {ApyUSD} from "./ApyUSD.sol";
import {CommitToken} from "./CommitToken.sol";
import {MinterV0} from "./MinterV0.sol";
import {IMinterV0} from "./interfaces/IMinterV0.sol";
import {IVesting} from "./interfaces/IVesting.sol";
import {IAddressList} from "./interfaces/IAddressList.sol";
import {IYieldDistributor} from "./interfaces/IYieldDistributor.sol";
import {IRedemptionPool} from "./interfaces/IRedemptionPool.sol";
import {RedemptionPoolV0} from "./RedemptionPoolV0.sol";

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

    /// @notice Redeemer role - granted to addresses that can perform redemptions
    /// @dev Can call RedemptionPoolV0.redeem() to burn asset and pay out reserve
    uint64 public constant ROLE_REDEEMER = 8;

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
        self.setRoleAdmin(ROLE_REDEEMER, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for ApxUSD contract (extension function)
     * @param self The AccessManager contract
     * @param apxUSD The ApxUSD contract
     */
    function assignAdminTargetsFor(AccessManager self, ApxUSD apxUSD) internal {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = ApxUSD.pause.selector;
        selectors[1] = ApxUSD.unpause.selector;
        selectors[2] = ApxUSD.setSupplyCap.selector;
        selectors[3] = ApxUSD.setDenyList.selector;
        self.setTargetFunctionRole(address(apxUSD), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for MinterV0 contract (extension function)
     * @param self The AccessManager contract
     * @param minterContract The MinterV0 contract
     */
    function assignAdminTargetsFor(AccessManager self, IMinterV0 minterContract) internal {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = IMinterV0.setMaxMintAmount.selector;
        selectors[1] = IMinterV0.setRateLimit.selector;
        selectors[2] = MinterV0.pause.selector;
        selectors[3] = MinterV0.unpause.selector;
        self.setTargetFunctionRole(address(minterContract), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns admin function selectors for ApyUSD contract (extension function)
     * @param self The AccessManager contract
     * @param apyUSD The ApyUSD contract
     */
    function assignAdminTargetsFor(AccessManager self, ApyUSD apyUSD) internal {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ApyUSD.pause.selector;
        selectors[1] = ApyUSD.unpause.selector;

        selectors[2] = ApyUSD.setDenyList.selector;
        selectors[3] = ApyUSD.setUnlockToken.selector;
        selectors[4] = ApyUSD.setVesting.selector;
        selectors[5] = ApyUSD.setUnlockingFee.selector;
        selectors[6] = ApyUSD.setFeeWallet.selector;
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
     * @notice Assigns admin function selectors for CommitToken contract (extension function)
     * @param self The AccessManager contract
     * @param commitToken The CommitToken contract (or subclass like UnlockToken)
     */
    function assignAdminTargetsFor(AccessManager self, CommitToken commitToken) internal {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = CommitToken.setUnlockingDelay.selector;
        selectors[1] = CommitToken.setDenyList.selector;
        selectors[2] = CommitToken.setSupplyCap.selector;
        selectors[3] = CommitToken.pause.selector;
        selectors[4] = CommitToken.unpause.selector;
        self.setTargetFunctionRole(address(commitToken), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns ADMIN_ROLE function selectors for YieldDistributor contract (extension function)
     * @param self The AccessManager contract
     * @param yieldDistributor The YieldDistributor contract
     */
    function assignAdminTargetsFor(AccessManager self, IYieldDistributor yieldDistributor) internal {
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IYieldDistributor.setVesting.selector;
        selectors[1] = IYieldDistributor.setSigningDelegate.selector;
        self.setTargetFunctionRole(address(yieldDistributor), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns ADMIN_ROLE function selectors for IRedemptionPool contract (extension function)
     * @param self The AccessManager contract
     * @param pool The IRedemptionPool contract
     */
    function assignAdminTargetsFor(AccessManager self, RedemptionPoolV0 pool) internal {
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = RedemptionPoolV0.deposit.selector;
        selectors[1] = RedemptionPoolV0.withdraw.selector;
        selectors[2] = RedemptionPoolV0.withdrawTokens.selector;
        selectors[3] = RedemptionPoolV0.setExchangeRate.selector;
        selectors[4] = RedemptionPoolV0.pause.selector;
        selectors[5] = RedemptionPoolV0.unpause.selector;
        self.setTargetFunctionRole(address(pool), selectors, ADMIN_ROLE);
    }

    /**
     * @notice Assigns MINTER_ROLE function selectors for MinterV0 contract (extension function)
     * @param self The AccessManager contract
     * @param minterContract The MinterV0 contract
     */
    function assignMinterTargetsFor(AccessManager self, IMinterV0 minterContract) internal {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = IMinterV0.requestMint.selector;
        selectors[1] = IMinterV0.executeMint.selector;
        selectors[2] = IMinterV0.cleanMintHistory.selector;
        selectors[3] = IMinterV0.cancelMint.selector;
        self.setTargetFunctionRole(address(minterContract), selectors, MINTER_ROLE);
    }

    /**
     * @notice Assigns mint guard function selectors for MinterV0 contract (extension function)
     * @param self The AccessManager contract
     * @param minterContract The MinterV0 contract
     * @dev cancelMint is now assigned to MINTER_ROLE to allow minters to clear expired orders
     */
    function assignMintGuardTargetsFor(AccessManager self, IMinterV0 minterContract) internal {
        // cancelMint has been moved to MINTER_ROLE to prevent deadlock when operation queue fills
        // MINT_GUARD_ROLE retains all other guardian functions if added in the future
        bytes4[] memory selectors = new bytes4[](0);
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

    /**
     * @notice Assigns ADMIN_ROLE and ROLE_REDEEMER function selectors for RedemptionPool contract (extension function)
     * @param self The AccessManager contract
     * @param pool The RedemptionPool contract (e.g. RedemptionPoolV0)
     */
    function assignRedeemerTargetsFor(AccessManager self, IRedemptionPool pool) internal {
        bytes4[] memory redeemerSelectors = new bytes4[](1);
        redeemerSelectors[0] = IRedemptionPool.redeem.selector;
        self.setTargetFunctionRole(address(pool), redeemerSelectors, ROLE_REDEEMER);
    }
}
