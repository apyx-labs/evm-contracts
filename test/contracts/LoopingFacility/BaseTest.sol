// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MarketParams, Id} from "morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "morpho-blue/src/libraries/MarketParamsLib.sol";

import {LoopingFacility} from "../../../src/LoopingFacility.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockMorpho} from "../../mocks/MockMorpho.sol";
import {MockAddressList} from "../../mocks/MockAddressList.sol";
import {MockSwapAdapter} from "../../mocks/MockSwapAdapter.sol";

abstract contract LoopingFacilityBaseTest is Test {
    using MarketParamsLib for MarketParams;

    uint256 internal constant LLTV = 0.86e18;
    uint256 internal constant INITIAL_SLIPPAGE_BPS = 50;
    uint256 internal constant MORPHO_LIQUIDITY = 100_000_000e18;
    uint256 internal constant ADAPTER_LIQUIDITY = 10_000_000e18;

    AccessManager public accessManager;
    MockERC20 public loanToken;
    MockERC20 public collateralToken;
    MockMorpho public morpho;
    MockAddressList public denyList;
    MockSwapAdapter public toCollateral;    // loanToken → collateralToken
    MockSwapAdapter public fromCollateral;  // collateralToken → loanToken
    LoopingFacility public loopingFacility;

    MarketParams public marketParams;
    Id public marketId;

    address public admin;
    address public alice;
    address public bob;

    function setUp() public virtual {
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.startPrank(admin);

        accessManager = new AccessManager(admin);
        loanToken = new MockERC20("Loan Token", "LOAN");
        collateralToken = new MockERC20("Collateral Token", "COLL");
        morpho = new MockMorpho(IERC20(address(loanToken)), IERC20(address(collateralToken)));
        denyList = new MockAddressList();

        toCollateral = new MockSwapAdapter(IERC20(address(loanToken)), IERC20(address(collateralToken)));
        fromCollateral = new MockSwapAdapter(IERC20(address(collateralToken)), IERC20(address(loanToken)));

        marketParams = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: address(0),
            irm: address(0),
            lltv: LLTV
        });
        marketId = marketParams.id();

        loopingFacility = new LoopingFacility(address(accessManager), morpho, denyList);

        // Register the market on LoopingFacility
        loopingFacility.addMarket(marketParams, toCollateral, fromCollateral, INITIAL_SLIPPAGE_BPS);

        // Seed MockMorpho with loan tokens for flash loans
        loanToken.mint(admin, MORPHO_LIQUIDITY);
        loanToken.approve(address(morpho), MORPHO_LIQUIDITY);
        morpho.seedLiquidity(MORPHO_LIQUIDITY);

        // Seed fromCollateral adapter with loan tokens (pays out during unwind)
        loanToken.mint(admin, ADAPTER_LIQUIDITY);
        loanToken.approve(address(fromCollateral), ADAPTER_LIQUIDITY);
        fromCollateral.seed(ADAPTER_LIQUIDITY);

        // Seed toCollateral adapter with collateral tokens (pays out during loop-up)
        collateralToken.mint(admin, ADAPTER_LIQUIDITY);
        collateralToken.approve(address(toCollateral), ADAPTER_LIQUIDITY);
        toCollateral.seed(ADAPTER_LIQUIDITY);

        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// @dev Give a user collateral and wire up all authorizations.
    function _setupUser(address user, uint256 collateralAmount) internal {
        collateralToken.mint(user, collateralAmount);
        vm.startPrank(user);
        collateralToken.approve(address(loopingFacility), type(uint256).max);
        morpho.setAuthorization(address(loopingFacility), true);
        vm.stopPrank();
    }

    /// @dev Open a looped position for a user at the given leverage.
    function _openPosition(address user, uint256 collateral, uint256 targetLeverage) internal {
        _setupUser(user, collateral);
        vm.prank(user);
        loopingFacility.loop(marketId, collateral, targetLeverage);
    }

    function _currentLeverage(address user) internal view returns (uint256) {
        (,, uint128 collateral) = _positionRaw(user);
        if (collateral == 0) return 0;
        uint256 debt = _debtAssets(user);
        uint256 collateralInLoanTerms = fromCollateral.quoteOut(collateral);
        uint256 equity = collateralInLoanTerms - debt;
        return collateralInLoanTerms * 1e18 / equity;
    }

    function _debtAssets(address user) internal view virtual returns (uint256) {
        (, uint128 shares,) = _positionRaw(user);
        return shares; // 1:1 in MockMorpho
    }

    function _positionRaw(address user) internal view virtual returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral) {
        supplyShares = morpho.position(marketId, user).supplyShares;
        borrowShares = morpho.position(marketId, user).borrowShares;
        collateral = morpho.position(marketId, user).collateral;
    }
}
