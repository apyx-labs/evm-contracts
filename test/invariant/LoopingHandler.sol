// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {LoopingFacility} from "../../src/LoopingFacility.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockApyUSD} from "../mocks/MockApyUSD.sol";
import {MockMorpho} from "../mocks/MockMorpho.sol";

/// @dev Stateful fuzzing handler for LoopingFacility invariant tests.
///
///      Manages a pool of actors, each with an independent position. The fuzzer drives
///      sequences of loop() and unwind() calls via the handler's public functions.
///      Ghost variables track aggregate position state for the invariant assertions.
contract LoopingHandler is Test {
    struct Actor {
        address addr;
        bool hasPosition;
    }

    LoopingFacility public immutable loopingFacility;
    MockERC20 public immutable apxUSD;
    MockApyUSD public immutable apyUSD;
    MockMorpho public immutable morpho;

    Actor[] public actors;
    Actor public currentActor;

    // Ghost variables — tracked by the handler and compared against invariants
    uint256 public ghost_loopCount;
    uint256 public ghost_unwindCount;
    uint256 public ghost_fullExitCount;

    function setUp() public virtual {}

    constructor(
        LoopingFacility _loopingFacility,
        MockERC20 _apxUSD,
        MockApyUSD _apyUSD,
        MockMorpho _morpho,
        uint256 actorCount
    ) {
        loopingFacility = _loopingFacility;
        apxUSD = _apxUSD;
        apyUSD = _apyUSD;
        morpho = _morpho;

        for (uint256 i = 0; i < actorCount; i++) {
            address addr = makeAddr(string.concat("looping_actor_", Strings.toString(i)));
            actors.push(Actor({addr: addr, hasPosition: false}));

            // Wire up each actor: approve and authorize once at setup time
            vm.startPrank(addr);
            apyUSD.approve(address(_loopingFacility), type(uint256).max);
            _morpho.setAuthorization(address(_loopingFacility), true);
            vm.stopPrank();
        }
    }

    // -------------------------------------------------------------------------
    // Handler actions
    // -------------------------------------------------------------------------

    /// @dev Open or increase a leveraged position for a randomly chosen actor.
    function loop(uint256 actorIndex, uint256 collateral, uint256 targetLeverage) public {
        uint256 idx = bound(actorIndex, 0, actors.length - 1);
        currentActor = actors[idx];
        address user = currentActor.addr;

        uint256 maxLev = loopingFacility.maxLeverage();
        uint256 currentLev = _currentLeverage(user);

        // Must target strictly above current and at or below max.
        if (currentLev >= maxLev || currentLev + 1 > maxLev) return;
        targetLeverage = bound(targetLeverage, currentLev + 1, maxLev);

        // For a fresh position, we must provide collateral
        if (!currentActor.hasPosition) {
            collateral = bound(collateral, 1e18, 10_000e18);
            _giveApyUSD(user, collateral);
        } else {
            collateral = 0; // existing positions don't need more collateral
        }

        vm.prank(user);
        try loopingFacility.loop(collateral, targetLeverage) {
            actors[idx].hasPosition = true;
            ghost_loopCount++;
        } catch {
            // Reverts are acceptable — bound() can produce edge cases the contract rejects
        }
    }

    /// @dev Partially unwind an existing position for a randomly chosen actor.
    function unwindPartial(uint256 actorIndex, uint256 targetLeverage) public {
        uint256 idx = bound(actorIndex, 0, actors.length - 1);
        currentActor = actors[idx];
        address user = currentActor.addr;

        if (!currentActor.hasPosition) return;

        uint256 currentLev = _currentLeverage(user);
        // Need at least 2 units of leverage headroom: bound(x, 1e18, currentLev - 1) requires currentLev > 1e18.
        if (currentLev <= 1e18 + 1) return;

        // Allow unwind all the way down to 1x (targetLeverage = 1e18).
        targetLeverage = bound(targetLeverage, 1e18, currentLev - 1);

        vm.prank(user);
        try loopingFacility.unwind(targetLeverage) {
            ghost_unwindCount++;
        } catch {}
    }

    /// @dev Fully exit an existing position for a randomly chosen actor.
    function unwindFull(uint256 actorIndex) public {
        uint256 idx = bound(actorIndex, 0, actors.length - 1);
        currentActor = actors[idx];
        address user = currentActor.addr;

        if (!currentActor.hasPosition) return;

        vm.prank(user);
        try loopingFacility.unwind(0) {
            actors[idx].hasPosition = false;
            ghost_fullExitCount++;
        } catch {}
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _getActor(uint256 index) internal view returns (Actor memory) {
        return actors[bound(index, 0, actors.length - 1)];
    }

    function _currentLeverage(address user) internal view returns (uint256) {
        (,, uint128 collateral) = _positionRaw(user);
        if (collateral == 0) return 1e18; // no position = 1x by convention
        uint256 debt = _debtAssets(user);
        uint256 rate = apyUSD.convertToAssets(1e18);
        uint256 collateralApxUSD = uint256(collateral) * rate / 1e18;
        if (collateralApxUSD <= debt) return type(uint256).max; // underwater
        return collateralApxUSD * 1e18 / (collateralApxUSD - debt);
    }

    function _debtAssets(address user) internal view returns (uint256) {
        (, uint128 shares,) = _positionRaw(user);
        return shares; // 1:1 in MockMorpho
    }

    function _positionRaw(address user)
        internal
        view
        returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral)
    {
        supplyShares = morpho.position(loopingFacility.marketId(), user).supplyShares;
        borrowShares = morpho.position(loopingFacility.marketId(), user).borrowShares;
        collateral = morpho.position(loopingFacility.marketId(), user).collateral;
    }

    function _giveApyUSD(address user, uint256 amount) internal {
        apxUSD.mint(user, amount);
        vm.startPrank(user);
        apxUSD.approve(address(apyUSD), amount);
        apyUSD.deposit(amount, user);
        vm.stopPrank();
    }
}
