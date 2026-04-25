// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Id} from "morpho-blue/src/interfaces/IMorpho.sol";

import {LoopingFacility} from "../../src/LoopingFacility.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockMorpho} from "../mocks/MockMorpho.sol";
import {MockSwapAdapter} from "../mocks/MockSwapAdapter.sol";

/// @dev Stateful fuzzing handler for LoopingFacility invariant tests.
contract LoopingHandler is Test {
    struct Actor {
        address addr;
        bool hasPosition;
    }

    LoopingFacility public immutable loopingFacility;
    MockERC20 public immutable loanToken;
    MockERC20 public immutable collateralToken;
    MockMorpho public immutable morpho;
    MockSwapAdapter public immutable fromCollateral;
    Id public immutable marketId;

    Actor[] public actors;
    Actor public currentActor;

    uint256 public ghost_loopCount;
    uint256 public ghost_unwindCount;
    uint256 public ghost_fullExitCount;

    function setUp() public virtual {}

    constructor(
        LoopingFacility _loopingFacility,
        MockERC20 _loanToken,
        MockERC20 _collateralToken,
        MockMorpho _morpho,
        MockSwapAdapter _fromCollateral,
        Id _marketId,
        uint256 actorCount
    ) {
        loopingFacility = _loopingFacility;
        loanToken = _loanToken;
        collateralToken = _collateralToken;
        morpho = _morpho;
        fromCollateral = _fromCollateral;
        marketId = _marketId;

        for (uint256 i = 0; i < actorCount; i++) {
            address addr = makeAddr(string.concat("looping_actor_", Strings.toString(i)));
            actors.push(Actor({addr: addr, hasPosition: false}));

            vm.startPrank(addr);
            collateralToken.approve(address(_loopingFacility), type(uint256).max);
            _morpho.setAuthorization(address(_loopingFacility), true);
            vm.stopPrank();
        }
    }

    // -------------------------------------------------------------------------
    // Handler actions
    // -------------------------------------------------------------------------

    function loop(uint256 actorIndex, uint256 collateral, uint256 targetLeverage) public {
        uint256 idx = bound(actorIndex, 0, actors.length - 1);
        currentActor = actors[idx];
        address user = currentActor.addr;

        uint256 maxLev = loopingFacility.maxLeverage(marketId);
        uint256 currentLev = _currentLeverage(user);

        if (currentLev >= maxLev || currentLev + 1 > maxLev) return;
        targetLeverage = bound(targetLeverage, currentLev + 1, maxLev);

        if (!currentActor.hasPosition) {
            collateral = bound(collateral, 1e18, 10_000e18);
            collateralToken.mint(user, collateral);
        } else {
            collateral = 0;
        }

        vm.prank(user);
        try loopingFacility.loop(marketId, collateral, targetLeverage) {
            actors[idx].hasPosition = true;
            ghost_loopCount++;
        } catch {}
    }

    function unwindPartial(uint256 actorIndex, uint256 targetLeverage) public {
        uint256 idx = bound(actorIndex, 0, actors.length - 1);
        currentActor = actors[idx];
        address user = currentActor.addr;

        if (!currentActor.hasPosition) return;

        uint256 currentLev = _currentLeverage(user);
        if (currentLev <= 1e18 + 1) return;

        targetLeverage = bound(targetLeverage, 1e18, currentLev - 1);

        vm.prank(user);
        try loopingFacility.unwind(marketId, targetLeverage) {
            ghost_unwindCount++;
        } catch {}
    }

    function unwindFull(uint256 actorIndex) public {
        uint256 idx = bound(actorIndex, 0, actors.length - 1);
        currentActor = actors[idx];
        address user = currentActor.addr;

        if (!currentActor.hasPosition) return;

        vm.prank(user);
        try loopingFacility.unwind(marketId, 0) {
            actors[idx].hasPosition = false;
            ghost_fullExitCount++;
        } catch {}
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _currentLeverage(address user) internal view returns (uint256) {
        (,, uint128 collateral) = _positionRaw(user);
        if (collateral == 0) return 1e18;
        uint256 debt = _debtAssets(user);
        uint256 collateralInLoanTerms = fromCollateral.quoteOut(collateral);
        if (collateralInLoanTerms <= debt) return type(uint256).max;
        return collateralInLoanTerms * 1e18 / (collateralInLoanTerms - debt);
    }

    function _debtAssets(address user) internal view returns (uint256) {
        (, uint128 shares,) = _positionRaw(user);
        return shares;
    }

    function _positionRaw(address user) internal view returns (uint256, uint128, uint128) {
        return (
            morpho.position(marketId, user).supplyShares,
            morpho.position(marketId, user).borrowShares,
            morpho.position(marketId, user).collateral
        );
    }
}
