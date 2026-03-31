// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IBridgedToken} from "./IBridgedToken.sol";
import {Roles} from "../Roles.sol";

/**
 * @title BridgeRoles
 * @notice Role definitions and AccessManager helpers for the Chainlink CCIP bridge layer.
 *
 * @dev Complements Roles.sol — keeps bridge-specific access config separate from the
 *      core protocol roles to avoid growing Roles.sol further.
 *
 *      Note: mint(), burn(uint256), and burnFrom(address,uint256) are no longer gated
 *      via AccessManager — they use the `onlyCCIPPool` modifier in BridgedApyxToken
 *      directly (single SLOAD, no external call) to stay within the CCIP OffRamp's
 *      90k gas budget. ROLE_CCIP_POOL and assignCCIPPoolTargetsFor are removed.
 *
 * Usage alongside Roles.sol:
 *
 *   using Roles for AccessManager;
 *   using BridgeRoles for AccessManager;
 *
 *   // Core protocol setup
 *   accessManager.setRoleAdmins();
 *   accessManager.assignAdminTargetsFor(apxUSD);
 *   ...
 *
 *   // Bridge setup (repeat for each BridgedApyxToken deployment)
 *   accessManager.assignAdminTargetsFor(bridgedToken);     // IBridgedToken overload
 */
library BridgeRoles {
    // ── AccessManager helpers ─────────────────────────────────────────────

    /// @notice Gates admin functions to ADMIN_ROLE on a bridged token.
    /// @dev Covers supply cap management, pause/unpause, CCIP admin/pool rotation,
    ///      and UUPS upgrades.
    function assignAdminTargetsFor(AccessManager self, IBridgedToken token) internal {
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = IBridgedToken.setSupplyCap.selector;
        selectors[1] = IBridgedToken.pause.selector;
        selectors[2] = IBridgedToken.unpause.selector;
        selectors[3] = IBridgedToken.setCCIPAdmin.selector;
        selectors[4] = IBridgedToken.setCCIPPool.selector;
        selectors[5] = UUPSUpgradeable.upgradeToAndCall.selector;
        self.setTargetFunctionRole(address(token), selectors, Roles.ADMIN_ROLE);
    }
}
