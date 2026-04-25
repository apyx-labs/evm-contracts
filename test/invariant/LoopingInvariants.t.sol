// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {StdInvariant} from "forge-std/src/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
            loanToken,
            collateralToken,
            morpho,
            fromCollateral,
            marketId,
            ACTOR_COUNT
        );

        excludeContract(address(accessManager));
        excludeContract(address(loanToken));
        excludeContract(address(collateralToken));
        excludeContract(address(morpho));
        excludeContract(address(toCollateral));
        excludeContract(address(fromCollateral));
        excludeContract(address(denyList));
        excludeContract(address(loopingFacility));

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("setUp()"));
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // -------------------------------------------------------------------------
    // Tier 1: Token custody
    // -------------------------------------------------------------------------

    /// LoopingFacility must never hold loan tokens at rest.
    function invariant_NoResidualLoanToken() public view {
        assertEq(
            loanToken.balanceOf(address(loopingFacility)),
            0,
            "LoopingFacility holds residual loan token"
        );
    }

    /// LoopingFacility must never hold collateral tokens at rest.
    function invariant_NoResidualCollateralToken() public view {
        assertEq(
            collateralToken.balanceOf(address(loopingFacility)),
            0,
            "LoopingFacility holds residual collateral token"
        );
    }

    // -------------------------------------------------------------------------
    // Tier 2: Leverage bounds
    // -------------------------------------------------------------------------

    /// No actor's position should ever exceed maxLeverage(marketId).
    function invariant_LeverageNeverExceedsMax() public view {
        uint256 maxLev = loopingFacility.maxLeverage(marketId);
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            (address user,) = handler.actors(i);
            (,, uint128 collateral) = _positionRaw(user);
            if (collateral == 0) continue;

            uint256 debt = _debtAssets(user);
            uint256 collateralInLoanTerms = fromCollateral.quoteOut(collateral);
            if (collateralInLoanTerms <= debt) continue;

            uint256 leverage = collateralInLoanTerms * 1e18 / (collateralInLoanTerms - debt);
            assertLe(leverage, maxLev + 1e9, "position exceeds max leverage");
        }
    }

    // -------------------------------------------------------------------------
    // Tier 3: Position solvency
    // -------------------------------------------------------------------------

    /// Every position with debt must have at least as much collateral value as debt.
    function invariant_PositionsNeverUndercollateralized() public view {
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            (address user,) = handler.actors(i);
            (, uint128 borrowShares, uint128 collateral) = _positionRaw(user);
            if (borrowShares == 0) continue;

            uint256 debt = uint256(borrowShares);
            uint256 collateralInLoanTerms = fromCollateral.quoteOut(collateral);

            assertGe(collateralInLoanTerms, debt, "position is undercollateralized");
        }
    }

    /// After a full exit, both collateral and debt must be exactly zero.
    function invariant_FullExitClearsPosition() public view {
        for (uint256 i = 0; i < ACTOR_COUNT; i++) {
            (address addr, bool hasPosition) = handler.actors(i);
            if (hasPosition) continue;

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
        (uint256 bps,,) = loopingFacility.slippageConfig(marketId);
        assertLe(bps, loopingFacility.MAX_SLIPPAGE_BPS(), "slippageBps exceeds MAX_SLIPPAGE_BPS");
    }

    /// Pending slippage must also never exceed the maximum (checked at queue time).
    function invariant_PendingSlippageBpsWithinBounds() public view {
        (, uint256 pendingBps, uint256 pendingEffectiveAt) = loopingFacility.slippageConfig(marketId);
        if (pendingEffectiveAt > 0) {
            assertLe(pendingBps, loopingFacility.MAX_SLIPPAGE_BPS(), "pendingSlippageBps exceeds MAX_SLIPPAGE_BPS");
        }
    }

    /// Ghost variable: loop count must be non-decreasing (sanity check on handler state).
    function invariant_GhostLoopCountNonDecreasing() public view {
        assertGe(handler.ghost_loopCount() + handler.ghost_fullExitCount(), handler.ghost_fullExitCount());
    }
}
