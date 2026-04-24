// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StdInvariant} from "forge-std/src/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MarketParams} from "morpho-blue/src/interfaces/IMorpho.sol";

import {LoopingFacilityBaseTest} from "../contracts/LoopingFacility/BaseTest.sol";
import {LoopingHandler} from "./LoopingHandler.sol";
import {LoopingFacility} from "../../src/LoopingFacility.sol";

contract LoopingInvariants is LoopingFacilityBaseTest {
    LoopingHandler public handler;

    uint256 private constant ACTOR_COUNT = 5;

    function setUp() public override {
        super.setUp();

        handler = new LoopingHandler(
            loopingFacility,
            apxUSD,
            apyUSD,
            morpho,
            ACTOR_COUNT
        );

        // Exclude all contracts except the handler from the fuzzer's target set
        excludeContract(address(accessManager));
        excludeContract(address(apxUSD));
        excludeContract(address(apyUSD));
        excludeContract(address(morpho));
        excludeContract(address(curvePool));
        excludeContract(address(denyList));
        excludeContract(address(loopingFacility));

        targetContract(address(handler));

        // Exclude setUp() from fuzz selectors on the handler
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("setUp()"));
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // -------------------------------------------------------------------------
    // Tier 1: Token custody
    // -------------------------------------------------------------------------

    /// LoopingFacility must never hold apxUSD at rest — tokens only pass through during callbacks.
    function invariant_NoResidualApxUSD() public view {
        assertEq(
            apxUSD.balanceOf(address(loopingFacility)),
            0,
            "LoopingFacility holds residual apxUSD"
        );
    }

    /// LoopingFacility must never hold apyUSD at rest.
    function invariant_NoResidualApyUSD() public view {
        assertEq(
            apyUSD.balanceOf(address(loopingFacility)),
            0,
            "LoopingFacility holds residual apyUSD"
        );
    }

    // -------------------------------------------------------------------------
    // Tier 2: Leverage bounds
    // -------------------------------------------------------------------------

    /// No actor's position should ever exceed maxLeverage().
    function invariant_LeverageNeverExceedsMax() public view {
        uint256 maxLev = loopingFacility.maxLeverage();
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            (address user,) = handler.actors(i);
            (,, uint128 collateral) = _positionRaw(user);
            if (collateral == 0) continue;

            uint256 debt = _debtAssets(user);
            uint256 rate = apyUSD.convertToAssets(1e18);
            uint256 collateralApxUSD = uint256(collateral) * rate / 1e18;
            if (collateralApxUSD <= debt) continue; // skip underwater (shouldn't happen)

            uint256 leverage = collateralApxUSD * 1e18 / (collateralApxUSD - debt);
            assertLe(leverage, maxLev + 1e9, "position exceeds max leverage");
        }
    }

    // -------------------------------------------------------------------------
    // Tier 3: Position solvency
    // -------------------------------------------------------------------------

    /// Every position with debt must have at least as much collateral value as debt.
    ///
    ///      In a real market the oracle would enforce this through liquidations, but here
    ///      we verify that the LoopingFacility itself never creates an underwater position.
    function invariant_PositionsNeverUndercollateralized() public view {
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            (address user,) = handler.actors(i);
            (, uint128 borrowShares, uint128 collateral) = _positionRaw(user);
            if (borrowShares == 0) continue;

            uint256 debt = borrowShares; // 1:1 in MockMorpho
            uint256 rate = apyUSD.convertToAssets(1e18);
            uint256 collateralApxUSD = uint256(collateral) * rate / 1e18;

            assertGe(collateralApxUSD, debt, "position is undercollateralized");
        }
    }

    /// After a full exit, both collateral and debt must be exactly zero.
    function invariant_FullExitClearsPosition() public view {
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            (address addr, bool hasPosition) = handler.actors(i);
            if (hasPosition) continue; // handler marks hasPosition=false after full exit

            (, uint128 borrowShares, uint128 collateral) = _positionRaw(addr);
            assertEq(collateral, 0, "collateral non-zero after full exit");
            assertEq(borrowShares, 0, "debt non-zero after full exit");
        }
    }

    // -------------------------------------------------------------------------
    // Tier 4: Config invariants
    // -------------------------------------------------------------------------

    /// Active slippage tolerance must never exceed the hard maximum.
    function invariant_SlippageBpsWithinBounds() public view {
        assertLe(
            loopingFacility.slippageBps(),
            loopingFacility.MAX_SLIPPAGE_BPS(),
            "slippageBps exceeds MAX_SLIPPAGE_BPS"
        );
    }

    /// Pending slippage must also never exceed the maximum (checked at queue time).
    function invariant_PendingSlippageBpsWithinBounds() public view {
        if (loopingFacility.pendingSlippageEffectiveAt() > 0) {
            assertLe(
                loopingFacility.pendingSlippageBps(),
                loopingFacility.MAX_SLIPPAGE_BPS(),
                "pendingSlippageBps exceeds MAX_SLIPPAGE_BPS"
            );
        }
    }

}
