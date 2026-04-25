// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAddressList} from "./interfaces/IAddressList.sol";
import {ISwapAdapter} from "./interfaces/ISwapAdapter.sol";
import {IMorpho, MarketParams, Position, Market, Id} from "morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {MarketParamsLib} from "morpho-blue/src/libraries/MarketParamsLib.sol";

import {EDenied} from "./errors/Denied.sol";
import {EInvalidAddress} from "./errors/InvalidAddress.sol";

/**
 * @title LoopingFacility
 * @notice Single-tx leverage management for any Morpho market.
 *         Users can loop up to a target leverage or unwind to any lower leverage (0 = full exit).
 *
 * @dev Each supported market is registered with two swap adapters:
 *        toCollateral   — converts the loan token into collateral (used during loop-up)
 *        fromCollateral — converts collateral back into the loan token (used during unwind)
 *
 *      This lets each market use the right mechanism: a vault deposit for apyUSD,
 *      Curve for stableswap pairs, Pendle for PT tokens, etc. The core flash loan
 *      math is the same regardless.
 *
 *      Leverage is WAD-scaled throughout: 1e18 = 1x, 2e18 = 2x, etc.
 *
 *      Users must call morpho.setAuthorization(address(this), true) before using this contract.
 */
contract LoopingFacility is AccessManaged, ReentrancyGuardTransient, IMorphoFlashLoanCallback, EDenied, EInvalidAddress {
    using SafeERC20 for IERC20;
    using MarketParamsLib for MarketParams;
    using Math for uint256;

    uint256 private constant WAD = 1e18;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    uint256 public constant MAX_SLIPPAGE_BPS = 1_000;
    uint256 public constant SLIPPAGE_COOLDOWN = 24 hours;

    /// @notice Gap below the market LLTV used when computing max leverage.
    uint256 private constant LLTV_SAFETY_BUFFER = 0.02e18;

    // -------------------------------------------------------------------------
    // Per-market config
    // -------------------------------------------------------------------------

    struct LoopMarket {
        MarketParams morphoParams;
        IERC20 loanToken;
        IERC20 collateralToken;
        ISwapAdapter toCollateral;    // loan → collateral (loop-up)
        ISwapAdapter fromCollateral;  // collateral → loan (unwind)
        bool enabled;
    }

    struct SlippageConfig {
        uint256 bps;
        uint256 pendingBps;
        uint256 pendingEffectiveAt;
    }

    // -------------------------------------------------------------------------
    // Flash loan callback data
    // -------------------------------------------------------------------------

    struct LoopCallbackData {
        Id marketId;
        address user;
    }

    struct UnwindCallbackData {
        Id marketId;
        address user;
        uint256 collateralToWithdraw;
        uint128 borrowShares;
        bool fullExit;
        uint256 debtToRepay;
        uint256 remainingCollateral;
        uint256 remainingDebt;
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    IMorpho public immutable morpho;
    IAddressList public immutable denyList;

    mapping(Id => LoopMarket) public markets;
    mapping(Id => SlippageConfig) public slippageConfig;

    /// @notice Non-zero only during a flash loan callback initiated by this contract.
    address private _flashInitiator;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event MarketAdded(Id indexed marketId, address loanToken, address collateralToken);
    event MarketEnabled(Id indexed marketId, bool enabled);
    event Looped(Id indexed marketId, address indexed user, uint256 totalCollateral, uint256 totalDebt, uint256 leverageWad);
    event Unwound(Id indexed marketId, address indexed user, uint256 totalCollateral, uint256 totalDebt, uint256 targetLeverageWad);
    event SlippageBpsQueued(Id indexed marketId, uint256 newBps, uint256 effectiveAt);
    event SlippageBpsApplied(Id indexed marketId, uint256 oldBps, uint256 newBps);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error MarketNotFound(Id marketId);
    error MarketDisabled(Id marketId);
    error UnauthorizedFlashLoan(address caller);
    error NoFlashLoanInitiator();
    error LeverageExceedsMax(uint256 requested, uint256 max);
    error LeverageMustIncrease(uint256 current, uint256 requested);
    error LeverageMustDecrease(uint256 current, uint256 requested);
    error NoCollateral();
    error SlippageExceedsMax(uint256 requested, uint256 max);
    error SlippageCooldownNotElapsed(uint256 effectiveAt, uint256 currentTime);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialAuthority, IMorpho morpho_, IAddressList denyList_)
        AccessManaged(initialAuthority)
    {
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
        if (address(morpho_) == address(0)) revert InvalidAddress("morpho");
        if (address(denyList_) == address(0)) revert InvalidAddress("denyList");

        morpho = morpho_;
        denyList = denyList_;
    }

    // -------------------------------------------------------------------------
    // Market management
    // -------------------------------------------------------------------------

    /**
     * @notice Register a new market. Both adapters and slippage must be configured upfront.
     * @param morphoParams      The Morpho market parameters.
     * @param toCollateral      Adapter: loan token → collateral (used on loop-up).
     * @param fromCollateral    Adapter: collateral → loan token (used on unwind).
     * @param initialSlippageBps Starting swap slippage tolerance for this market.
     */
    function addMarket(
        MarketParams memory morphoParams,
        ISwapAdapter toCollateral,
        ISwapAdapter fromCollateral,
        uint256 initialSlippageBps
    ) external restricted {
        if (address(toCollateral) == address(0)) revert InvalidAddress("toCollateral");
        if (address(fromCollateral) == address(0)) revert InvalidAddress("fromCollateral");
        if (initialSlippageBps > MAX_SLIPPAGE_BPS) revert SlippageExceedsMax(initialSlippageBps, MAX_SLIPPAGE_BPS);

        Id marketId = morphoParams.id();

        markets[marketId] = LoopMarket({
            morphoParams: morphoParams,
            loanToken: IERC20(morphoParams.loanToken),
            collateralToken: IERC20(morphoParams.collateralToken),
            toCollateral: toCollateral,
            fromCollateral: fromCollateral,
            enabled: true
        });

        slippageConfig[marketId].bps = initialSlippageBps;

        emit MarketAdded(marketId, morphoParams.loanToken, morphoParams.collateralToken);
    }

    /// @notice Enable or disable looping for a market without removing its config.
    function setMarketEnabled(Id marketId, bool enabled) external restricted {
        _requireMarketExists(marketId);
        markets[marketId].enabled = enabled;
        emit MarketEnabled(marketId, enabled);
    }

    // -------------------------------------------------------------------------
    // Loop up
    // -------------------------------------------------------------------------

    /**
     * @notice Increase leverage on a market to targetLeverage in a single transaction.
     *
     * @dev Leverage math (all in loan token terms):
     *        collateralValue = fromCollateral.quoteOut(totalCollateral)
     *        netEquity       = collateralValue - existingDebt
     *        flashAmount     = netEquity * targetLeverage / WAD - collateralValue
     *
     * @param marketId            The market to loop on.
     * @param additionalCollateral Collateral tokens to pull from the caller and add. Can be 0.
     * @param targetLeverage      WAD-scaled target (e.g. 2e18 = 2x). Must exceed current leverage.
     */
    function loop(Id marketId, uint256 additionalCollateral, uint256 targetLeverage) external nonReentrant {
        if (denyList.contains(msg.sender)) revert Denied(msg.sender);

        LoopMarket storage market = _requireMarketEnabled(marketId);

        morpho.accrueInterest(market.morphoParams);

        Position memory pos = morpho.position(marketId, msg.sender);
        Market memory mkt = morpho.market(marketId);
        uint256 existingDebt = _sharesToAssets(pos.borrowShares, mkt);

        if (additionalCollateral > 0) {
            market.collateralToken.safeTransferFrom(msg.sender, address(this), additionalCollateral);
            market.collateralToken.forceApprove(address(morpho), additionalCollateral);
            morpho.supplyCollateral(market.morphoParams, additionalCollateral, msg.sender, "");
        }

        uint256 totalCollateral = pos.collateral + additionalCollateral;
        if (totalCollateral == 0) revert NoCollateral();

        uint256 collateralInLoanTerms = _collateralToLoanTerms(market, totalCollateral);
        uint256 netEquity = collateralInLoanTerms - existingDebt;
        uint256 currentLeverage = collateralInLoanTerms.mulDiv(WAD, netEquity);

        if (targetLeverage <= currentLeverage) revert LeverageMustIncrease(currentLeverage, targetLeverage);
        uint256 maxLev = maxLeverage(marketId);
        if (targetLeverage > maxLev) revert LeverageExceedsMax(targetLeverage, maxLev);

        uint256 flashAmount = netEquity.mulDiv(targetLeverage, WAD) - collateralInLoanTerms;

        if (flashAmount == 0) {
            emit Looped(marketId, msg.sender, totalCollateral, existingDebt, currentLeverage);
            return;
        }

        _flashInitiator = msg.sender;
        morpho.flashLoan(
            address(market.loanToken),
            flashAmount,
            abi.encode(true, LoopCallbackData({marketId: marketId, user: msg.sender}))
        );
        delete _flashInitiator;

        emit Looped(marketId, msg.sender, pos.collateral + additionalCollateral, existingDebt + flashAmount, targetLeverage);
    }

    // -------------------------------------------------------------------------
    // Unwind
    // -------------------------------------------------------------------------

    /**
     * @notice Decrease leverage to targetLeverage in a single transaction. Pass 0 to exit fully.
     *
     * @param marketId       The market to unwind on.
     * @param targetLeverage WAD-scaled target. Must be below current leverage.
     */
    function unwind(Id marketId, uint256 targetLeverage) external nonReentrant {
        if (denyList.contains(msg.sender)) revert Denied(msg.sender);

        _requireMarketEnabled(marketId);

        morpho.accrueInterest(markets[marketId].morphoParams);

        UnwindCallbackData memory cb = _buildUnwindData(marketId, msg.sender, targetLeverage);

        _flashInitiator = msg.sender;
        morpho.flashLoan(
            address(markets[marketId].loanToken),
            cb.debtToRepay,
            abi.encode(false, cb)
        );
        delete _flashInitiator;

        emit Unwound(marketId, msg.sender, cb.remainingCollateral, cb.remainingDebt, targetLeverage);
    }

    function _buildUnwindData(Id marketId, address user, uint256 targetLeverage)
        private
        view
        returns (UnwindCallbackData memory cb)
    {
        LoopMarket storage market = markets[marketId];
        Position memory pos = morpho.position(marketId, user);
        Market memory mkt = morpho.market(marketId);

        if (pos.collateral == 0) revert NoCollateral();

        uint256 existingDebt = _sharesToAssets(pos.borrowShares, mkt);
        uint256 collateralInLoanTerms = _collateralToLoanTerms(market, pos.collateral);
        uint256 netEquity = collateralInLoanTerms - existingDebt;
        uint256 currentLeverage = collateralInLoanTerms.mulDiv(WAD, netEquity);

        if (targetLeverage >= currentLeverage) revert LeverageMustDecrease(currentLeverage, targetLeverage);

        cb.marketId = marketId;
        cb.user = user;
        cb.borrowShares = pos.borrowShares;
        cb.fullExit = targetLeverage == 0;

        if (cb.fullExit) {
            cb.debtToRepay = existingDebt;
            cb.collateralToWithdraw = pos.collateral;
            cb.remainingCollateral = 0;
            cb.remainingDebt = 0;
        } else {
            uint256 targetDebt = targetLeverage <= WAD ? 0 : netEquity.mulDiv(targetLeverage - WAD, WAD);
            cb.debtToRepay = existingDebt - targetDebt;
            // quoteIn gives the collateral needed so the swap output covers the flash repayment exactly.
            cb.collateralToWithdraw = market.fromCollateral.quoteIn(cb.debtToRepay);
            cb.remainingCollateral = pos.collateral - cb.collateralToWithdraw;
            cb.remainingDebt = existingDebt - cb.debtToRepay;
        }
    }

    // -------------------------------------------------------------------------
    // Flash loan callback
    // -------------------------------------------------------------------------

    /**
     * @notice Called by Morpho mid-flash-loan.
     * @dev Two security checks:
     *      - msg.sender must be Morpho
     *      - _flashInitiator must be set (rules out external flashLoan calls)
     */
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        if (msg.sender != address(morpho)) revert UnauthorizedFlashLoan(msg.sender);
        if (_flashInitiator == address(0)) revert NoFlashLoanInitiator();

        bool isLoop = abi.decode(data[:32], (bool));

        if (isLoop) {
            (, LoopCallbackData memory cb) = abi.decode(data, (bool, LoopCallbackData));
            _handleLoop(assets, cb);
        } else {
            (, UnwindCallbackData memory cb) = abi.decode(data, (bool, UnwindCallbackData));
            _handleUnwind(assets, cb);
        }
    }

    function _handleLoop(uint256 flashAmount, LoopCallbackData memory cb) internal {
        LoopMarket storage market = markets[cb.marketId];
        SlippageConfig storage slip = slippageConfig[cb.marketId];

        // Approve the adapter and swap loan token → collateral.
        uint256 expectedCollateral = market.toCollateral.quoteOut(flashAmount);
        uint256 minCollateral = expectedCollateral.mulDiv(BPS_DENOMINATOR - slip.bps, BPS_DENOMINATOR);

        market.loanToken.forceApprove(address(market.toCollateral), flashAmount);
        uint256 collateralReceived = market.toCollateral.swap(flashAmount, minCollateral, address(this));

        // Supply received collateral to Morpho on the user's behalf.
        market.collateralToken.forceApprove(address(morpho), collateralReceived);
        morpho.supplyCollateral(market.morphoParams, collateralReceived, cb.user, "");

        // Borrow back exactly the flash amount so we can repay Morpho.
        morpho.borrow(market.morphoParams, flashAmount, 0, cb.user, address(this));

        // Approve Morpho to pull the flash repayment. Callback ends here and Morpho settles.
        market.loanToken.forceApprove(address(morpho), flashAmount);
    }

    function _handleUnwind(uint256 debtToRepay, UnwindCallbackData memory cb) internal {
        LoopMarket storage market = markets[cb.marketId];
        SlippageConfig storage slip = slippageConfig[cb.marketId];

        // Repay the debt. Full exit uses shares to guarantee zero dust.
        market.loanToken.forceApprove(address(morpho), debtToRepay);
        if (cb.fullExit) {
            morpho.repay(market.morphoParams, 0, cb.borrowShares, cb.user, "");
        } else {
            morpho.repay(market.morphoParams, debtToRepay, 0, cb.user, "");
        }

        // Withdraw the sized collateral from the user's position.
        morpho.withdrawCollateral(market.morphoParams, cb.collateralToWithdraw, cb.user, address(this));

        // Swap collateral → loan token. Enforce slippage but never accept less than debtToRepay
        // (we need exactly that much to repay the flash loan).
        uint256 expectedOut = market.fromCollateral.quoteOut(cb.collateralToWithdraw);
        uint256 minOut = expectedOut.mulDiv(BPS_DENOMINATOR - slip.bps, BPS_DENOMINATOR);
        if (minOut < debtToRepay) minOut = debtToRepay;

        market.collateralToken.forceApprove(address(market.fromCollateral), cb.collateralToWithdraw);
        uint256 received = market.fromCollateral.swap(cb.collateralToWithdraw, minOut, address(this));

        // Return any surplus to the user (recovered equity above what's needed for the flash repayment).
        uint256 surplus = received - debtToRepay;
        if (surplus > 0) market.loanToken.safeTransfer(cb.user, surplus);

        // Approve Morpho to pull the flash repayment.
        market.loanToken.forceApprove(address(morpho), debtToRepay);
    }

    // -------------------------------------------------------------------------
    // Slippage configuration (per market)
    // -------------------------------------------------------------------------

    /**
     * @notice Queue a new slippage tolerance for a market. Active after SLIPPAGE_COOLDOWN.
     * @param marketId The market to configure.
     * @param newBps   Basis points (e.g. 50 = 0.5%). Cannot exceed MAX_SLIPPAGE_BPS.
     */
    function setSlippageBps(Id marketId, uint256 newBps) external restricted {
        _requireMarketExists(marketId);
        if (newBps > MAX_SLIPPAGE_BPS) revert SlippageExceedsMax(newBps, MAX_SLIPPAGE_BPS);
        slippageConfig[marketId].pendingBps = newBps;
        slippageConfig[marketId].pendingEffectiveAt = block.timestamp + SLIPPAGE_COOLDOWN;
        emit SlippageBpsQueued(marketId, newBps, slippageConfig[marketId].pendingEffectiveAt);
    }

    /// @notice Activate the pending slippage value for a market after the cooldown has elapsed.
    function applySlippageBps(Id marketId) external restricted {
        _requireMarketExists(marketId);
        SlippageConfig storage cfg = slippageConfig[marketId];
        if (block.timestamp < cfg.pendingEffectiveAt) {
            revert SlippageCooldownNotElapsed(cfg.pendingEffectiveAt, block.timestamp);
        }
        uint256 oldBps = cfg.bps;
        cfg.bps = cfg.pendingBps;
        emit SlippageBpsApplied(marketId, oldBps, cfg.bps);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Maximum leverage for a market, derived from its LLTV with a safety buffer.
     * @dev maxLev = WAD / (WAD - (lltv - LLTV_SAFETY_BUFFER))
     *      E.g. LLTV = 86%, buffer = 2% → effective = 84% → maxLev = 6.25x
     */
    function maxLeverage(Id marketId) public view returns (uint256) {
        uint256 lltv = markets[marketId].morphoParams.lltv;
        return WAD.mulDiv(WAD, WAD - (lltv - LLTV_SAFETY_BUFFER));
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _requireMarketExists(Id marketId) internal view {
        if (address(markets[marketId].loanToken) == address(0)) revert MarketNotFound(marketId);
    }

    function _requireMarketEnabled(Id marketId) internal view returns (LoopMarket storage market) {
        market = markets[marketId];
        if (address(market.loanToken) == address(0)) revert MarketNotFound(marketId);
        if (!market.enabled) revert MarketDisabled(marketId);
    }

    /// @dev Converts a collateral token amount into loan token terms using the fromCollateral adapter.
    ///      quoteOut(collateral) gives loan tokens received — this is the value of collateral in the
    ///      loan token unit, which is what the leverage math operates on.
    function _collateralToLoanTerms(LoopMarket storage market, uint256 collateralAmount)
        internal
        view
        returns (uint256)
    {
        return market.fromCollateral.quoteOut(collateralAmount);
    }

    /// @dev accrueInterest() must be called before this for an accurate result.
    function _sharesToAssets(uint128 borrowShares, Market memory mkt) internal pure returns (uint256) {
        if (mkt.totalBorrowShares == 0) return 0;
        return uint256(borrowShares).mulDiv(mkt.totalBorrowAssets, mkt.totalBorrowShares);
    }
}
