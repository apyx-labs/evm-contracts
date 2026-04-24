// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MarketParams} from "morpho-blue/src/interfaces/IMorpho.sol";

import {LoopingFacility} from "../../../src/LoopingFacility.sol";
import {ICurveStableswapNG} from "../../../src/curve/ICurveStableswapNG.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockApyUSD} from "../../mocks/MockApyUSD.sol";
import {MockMorpho} from "../../mocks/MockMorpho.sol";
import {MockCurvePool} from "../../mocks/MockCurvePool.sol";
import {MockAddressList} from "../../mocks/MockAddressList.sol";

abstract contract LoopingFacilityBaseTest is Test {
    // LLTV = 86% → maxLeverage = 1 / (1 - 0.84) = 6.25x
    uint256 internal constant LLTV = 0.86e18;
    uint256 internal constant INITIAL_SLIPPAGE_BPS = 50; // 0.5%
    uint256 internal constant FLASH_LOAN_LIQUIDITY = 100_000_000e18;
    uint256 internal constant CURVE_LIQUIDITY = 10_000_000e18;

    AccessManager public accessManager;
    MockERC20 public apxUSD;
    MockApyUSD public apyUSD;
    MockMorpho public morpho;
    MockCurvePool public curvePool;
    MockAddressList public denyList;
    LoopingFacility public loopingFacility;

    MarketParams public marketParams;

    address public admin;
    address public alice;
    address public bob;
    address public attacker;

    function setUp() public virtual {
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        attacker = makeAddr("attacker");

        vm.startPrank(admin);

        accessManager = new AccessManager(admin);
        apxUSD = new MockERC20("Apyx USD", "apxUSD");
        apyUSD = new MockApyUSD(IERC20(address(apxUSD)));
        morpho = new MockMorpho(IERC20(address(apxUSD)), IERC20(address(apyUSD)));
        curvePool = new MockCurvePool(IERC20(address(apyUSD)), IERC20(address(apxUSD)));
        denyList = new MockAddressList();

        marketParams = MarketParams({
            loanToken: address(apxUSD),
            collateralToken: address(apyUSD),
            oracle: address(0),
            irm: address(0),
            lltv: LLTV
        });

        loopingFacility = new LoopingFacility(
            address(accessManager),
            morpho,
            IERC4626(address(apyUSD)),
            IERC20(address(apxUSD)),
            ICurveStableswapNG(address(curvePool)),
            marketParams,
            denyList,
            INITIAL_SLIPPAGE_BPS
        );

        // Fund MockMorpho with apxUSD for flash loans
        apxUSD.mint(admin, FLASH_LOAN_LIQUIDITY);
        apxUSD.approve(address(morpho), FLASH_LOAN_LIQUIDITY);
        morpho.seedLiquidity(FLASH_LOAN_LIQUIDITY);

        // Fund MockCurvePool with both tokens so exchange() can pay out
        apxUSD.mint(admin, CURVE_LIQUIDITY);
        apxUSD.approve(address(curvePool), CURVE_LIQUIDITY);
        apyUSD.approve(address(curvePool), CURVE_LIQUIDITY); // admin won't have apyUSD but seedLiquidity handles apyUSD separately

        // Seed only apxUSD side of the pool (unwind swaps apyUSD → apxUSD, pool needs apxUSD)
        apxUSD.approve(address(curvePool), type(uint256).max);
        curvePool.seedLiquidity(0, CURVE_LIQUIDITY);

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// @dev Give a user apyUSD collateral and wire up all authorizations.
    function _setupUser(address user, uint256 apyUSDAmount) internal {
        // Mint apxUSD to the user so they can deposit into MockApyUSD to get apyUSD
        apxUSD.mint(user, apyUSDAmount);
        vm.startPrank(user);
        apxUSD.approve(address(apyUSD), apyUSDAmount);
        apyUSD.deposit(apyUSDAmount, user);
        // Approve LoopingFacility to pull their apyUSD for additionalCollateral
        apyUSD.approve(address(loopingFacility), type(uint256).max);
        // Authorize LoopingFacility to borrow and withdraw on their behalf
        morpho.setAuthorization(address(loopingFacility), true);
        vm.stopPrank();
    }

    /// @dev Open a looped position for a user at the given leverage.
    function _openPosition(address user, uint256 collateral, uint256 targetLeverage) internal {
        _setupUser(user, collateral);
        vm.prank(user);
        loopingFacility.loop(collateral, targetLeverage);
    }

    function _currentLeverage(address user) internal view returns (uint256) {
        (,, uint128 collateral) = _positionRaw(user);
        uint256 debt = _debtAssets(user);
        if (collateral == 0) return 0;
        uint256 rate = apyUSD.convertToAssets(1e18);
        uint256 collateralApxUSD = uint256(collateral) * rate / 1e18;
        uint256 equity = collateralApxUSD - debt;
        return collateralApxUSD * 1e18 / equity;
    }

    function _debtAssets(address user) internal view virtual returns (uint256) {
        (, uint128 shares,) = _positionRaw(user);
        return shares; // 1:1 in MockMorpho
    }

    function _positionRaw(address user) internal view virtual returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral) {
        (supplyShares, borrowShares, collateral) = (
            morpho.position(loopingFacility.marketId(), user).supplyShares,
            morpho.position(loopingFacility.marketId(), user).borrowShares,
            morpho.position(loopingFacility.marketId(), user).collateral
        );
    }
}
