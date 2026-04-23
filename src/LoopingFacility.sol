// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAddressList} from "./interfaces/IAddressList.sol";
import {IMorpho, MarketParams, Position, Market, Id} from "morpho-blue/src/interfaces/IMorpho.sol";
import {IMorphoFlashLoanCallback} from "morpho-blue/src/interfaces/IMorphoCallbacks.sol";
import {MarketParamsLib} from "morpho-blue/src/libraries/MarketParamsLib.sol";
import {ICurveStableswapNG} from "./curve/ICurveStableswapNG.sol";

import {EDenied} from "./errors/Denied.sol";
import {EInvalidAddress} from "./errors/InvalidAddress.sol";

/**
 * @title LoopingFacility
 * @notice Single-tx leverage management for the apyUSD/apxUSD Morpho market.
 *         Users can loop up to a target leverage or unwind to any lower leverage (0 = full exit).
 *
 * @dev Looping works by flash-borrowing apxUSD, converting it to apyUSD collateral, and
 *      borrowing back enough apxUSD to repay the flash loan — all in one callback.
 *      On the way up we skip Curve entirely and deposit directly into the apyUSD ERC-4626 vault.
 *      On the way down we have to go through Curve because the vault's redeem path has a
 *      cooldown lock via UnlockToken, so atomic unwinding isn't possible through it.
 *
 *      Leverage is WAD-scaled throughout: 1e18 = 1x, 2e18 = 2x, etc.
 *
 *      Users must call morpho.setAuthorization(address(this), true) before using this contract —
 *      Morpho requires explicit authorization for borrow() and withdrawCollateral() when the
 *      caller isn't the position owner.
 */
contract LoopingFacility is AccessManaged, ReentrancyGuardTransient, IMorphoFlashLoanCallback, EDenied, EInvalidAddress {
    using SafeERC20 for IERC20;
    using MarketParamsLib for MarketParams;
    using Math for uint256;

    uint256 private constant WAD = 1e18;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice Hard ceiling on configurable slippage — 10%.
    uint256 public constant MAX_SLIPPAGE_BPS = 1_000;

    /// @notice Time between queueing and applying a slippage change.
    ///         Stops an admin from instantly dropping protection right before a large unwind.
    uint256 public constant SLIPPAGE_COOLDOWN = 24 hours;

    /// @notice Gap below the market LLTV used when computing max leverage.
    ///         Keeps newly opened positions a safe distance from the liquidation threshold.
    uint256 private constant LLTV_SAFETY_BUFFER = 0.02e18;

    int128 private constant APYUSD_INDEX = 0;
    int128 private constant APXUSD_INDEX = 1;

    IMorpho public immutable morpho;
    /// @notice apyUSD — the collateral. ERC-4626 vault whose share price grows as yield accrues.
    IERC4626 public immutable apyUSD;
    /// @notice apxUSD — the loan token.
    IERC20 public immutable apxUSD;
    /// @notice Curve StableswapNG pool: apyUSD at index 0, apxUSD at index 1.
    ICurveStableswapNG public immutable curvePool;
    IAddressList public immutable denyList;

    /// @notice Cannot be immutable — Solidity doesn't support immutable structs.
    ///         Never written after construction.
    MarketParams public marketParams;
    /// @notice Cached keccak256 of marketParams, avoids recomputing on every call.
    Id public marketId;

    /// @notice Active Curve swap slippage tolerance in basis points (e.g. 50 = 0.5%).
    uint256 public slippageBps;
    uint256 public pendingSlippageBps;
    uint256 public pendingSlippageEffectiveAt;

    /// @notice Non-zero only during the synchronous window of a flash loan call.
    ///         Lets the callback verify it was triggered by this contract, not an external caller.
    address private _flashInitiator;

    /// @notice Packed callback params for unwind — struct keeps unwind()'s stack under the 16-slot limit.
    struct UnwindCallbackData {
        address user;
        uint256 collateralToWithdrawApyUSD;
        /// @dev Passed through so the callback can do a shares-based full repay, avoiding dust.
        uint128 borrowShares;
        bool fullExit;
        uint256 debtToRepay;
        /// @dev Stored here to avoid re-reading position state after the flash loan returns.
        uint256 remainingCollateral;
        uint256 remainingDebt;
    }

    event Looped(address indexed user, uint256 totalCollateral, uint256 totalDebt, uint256 leverageWad);
    event Unwound(address indexed user, uint256 totalCollateral, uint256 totalDebt, uint256 targetLeverageWad);
    event SlippageBpsQueued(uint256 newBps, uint256 effectiveAt);
    event SlippageBpsApplied(uint256 oldBps, uint256 newBps);

    error UnauthorizedFlashLoan(address caller);
    error NoFlashLoanInitiator();
    error LeverageExceedsMax(uint256 requested, uint256 max);
    error LeverageMustIncrease(uint256 current, uint256 requested);
    error LeverageMustDecrease(uint256 current, uint256 requested);
    error NoCollateral();
    error SlippageExceedsMax(uint256 requested, uint256 max);
    error SlippageCooldownNotElapsed(uint256 effectiveAt, uint256 currentTime);

    /**
     * @param initialAuthority AccessManager governing restricted functions
     * @param morpho_ Morpho Blue core contract
     * @param apyUSD_ apyUSD ERC-4626 vault (collateral token)
     * @param apxUSD_ apxUSD ERC-20 (loan token)
     * @param curvePool_ Curve StableswapNG pool: apyUSD[0], apxUSD[1]
     * @param marketParams_ The Morpho apyUSD/apxUSD market
     * @param denyList_ Protocol deny list
     * @param initialSlippageBps Starting Curve swap slippage tolerance in bps
     */
    constructor(
        address initialAuthority,
        IMorpho morpho_,
        IERC4626 apyUSD_,
        IERC20 apxUSD_,
        ICurveStableswapNG curvePool_,
        MarketParams memory marketParams_,
        IAddressList denyList_,
        uint256 initialSlippageBps
    ) AccessManaged(initialAuthority) {
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
        if (address(morpho_) == address(0)) revert InvalidAddress("morpho");
        if (address(apyUSD_) == address(0)) revert InvalidAddress("apyUSD");
        if (address(apxUSD_) == address(0)) revert InvalidAddress("apxUSD");
        if (address(curvePool_) == address(0)) revert InvalidAddress("curvePool");
        if (address(denyList_) == address(0)) revert InvalidAddress("denyList");
        if (initialSlippageBps > MAX_SLIPPAGE_BPS) revert SlippageExceedsMax(initialSlippageBps, MAX_SLIPPAGE_BPS);

        morpho = morpho_;
        apyUSD = apyUSD_;
        apxUSD = apxUSD_;
        curvePool = curvePool_;
        denyList = denyList_;
        marketParams = marketParams_;
        marketId = marketParams_.id();
        slippageBps = initialSlippageBps;

        // Max approvals set once. This contract never holds tokens between transactions —
        // they only pass through during flash loan callbacks — so residual approvals aren't a concern.
        apxUSD_.approve(address(morpho_), type(uint256).max);   // flash loan repayment
        apxUSD_.approve(address(apyUSD_), type(uint256).max);   // deposit into vault on loop up
        IERC20(address(apyUSD_)).approve(address(morpho_), type(uint256).max);   // supplyCollateral
        IERC20(address(apyUSD_)).approve(address(curvePool_), type(uint256).max); // exchange on unwind
    }

    // -------------------------------------------------------------------------
    // Loop up
    // -------------------------------------------------------------------------

    /**
     * @notice Increase leverage to targetLeverage in a single transaction.
     *
     * @dev Leverage math (all in apxUSD terms):
     *        rate            = apyUSD.convertToAssets(WAD)
     *        totalCollateral = (existingCollateral + additionalCollateral) * rate / WAD
     *        netEquity       = totalCollateral - existingDebt
     *        flashAmount     = netEquity * targetLeverage / WAD - totalCollateral
     *
     * @param additionalCollateral apyUSD to pull from the caller and add as fresh collateral.
     *        Can be 0 if the caller already has an open position.
     * @param targetLeverage WAD-scaled target (e.g. 2e18 = 2x). Must exceed current leverage
     *        and be within maxLeverage().
     */
    function loop(uint256 additionalCollateral, uint256 targetLeverage) external nonReentrant {
        if (denyList.contains(msg.sender)) revert Denied(msg.sender);

        // Stale totalBorrowAssets would cause us to undercount existing debt.
        morpho.accrueInterest(marketParams);

        Position memory pos = morpho.position(marketId, msg.sender);
        Market memory mkt = morpho.market(marketId);
        uint256 existingDebt = _sharesToAssets(pos.borrowShares, mkt);

        if (additionalCollateral > 0) {
            IERC20(address(apyUSD)).safeTransferFrom(msg.sender, address(this), additionalCollateral);
            morpho.supplyCollateral(marketParams, additionalCollateral, msg.sender, "");
        }

        uint256 totalCollateralApyUSD = pos.collateral + additionalCollateral;
        if (totalCollateralApyUSD == 0) revert NoCollateral();

        uint256 rate = apyUSD.convertToAssets(WAD);
        uint256 totalCollateralApxUSD = totalCollateralApyUSD.mulDiv(rate, WAD);
        uint256 netEquityApxUSD = totalCollateralApxUSD - existingDebt;
        uint256 currentLeverage = totalCollateralApxUSD.mulDiv(WAD, netEquityApxUSD);

        if (targetLeverage <= currentLeverage) revert LeverageMustIncrease(currentLeverage, targetLeverage);
        uint256 maxLev = maxLeverage();
        if (targetLeverage > maxLev) revert LeverageExceedsMax(targetLeverage, maxLev);

        uint256 flashAmount = netEquityApxUSD.mulDiv(targetLeverage, WAD) - totalCollateralApxUSD;

        if (flashAmount == 0) {
            emit Looped(msg.sender, totalCollateralApyUSD, existingDebt, currentLeverage);
            return;
        }

        _flashInitiator = msg.sender;
        morpho.flashLoan(address(apxUSD), flashAmount, abi.encode(true, msg.sender, flashAmount));
        delete _flashInitiator;

        emit Looped(
            msg.sender,
            totalCollateralApyUSD + _apxUSDToApyUSD(flashAmount, rate),
            existingDebt + flashAmount,
            targetLeverage
        );
    }

    // -------------------------------------------------------------------------
    // Unwind
    // -------------------------------------------------------------------------

    /**
     * @notice Decrease leverage to targetLeverage in a single transaction.
     *         Pass 0 to exit the position entirely.
     *
     * @dev Unwind math (all in apxUSD terms):
     *        targetDebt                 = netEquity * (targetLeverage - WAD) / WAD  [0 if L ≤ 1x]
     *        debtToRepay                = existingDebt - targetDebt
     *        collateralToWithdrawApyUSD = get_dx(apyUSD → apxUSD, dy = debtToRepay)
     *
     *      get_dx gives the apyUSD amount that produces exactly debtToRepay apxUSD out of
     *      the Curve pool, fees included. Any swap output above debtToRepay goes back to the user.
     *
     * @param targetLeverage WAD-scaled target. Must be below current leverage.
     */
    function unwind(uint256 targetLeverage) external nonReentrant {
        if (denyList.contains(msg.sender)) revert Denied(msg.sender);

        morpho.accrueInterest(marketParams);

        // Computation split into a helper to keep this function's stack under the 16-slot limit.
        UnwindCallbackData memory cb = _buildUnwindData(msg.sender, targetLeverage);

        _flashInitiator = msg.sender;
        morpho.flashLoan(address(apxUSD), cb.debtToRepay, abi.encode(false, cb));
        delete _flashInitiator;

        emit Unwound(msg.sender, cb.remainingCollateral, cb.remainingDebt, targetLeverage);
    }

    /// @dev Pure computation — no state changes. Separated from unwind() to avoid a stack-too-deep error.
    function _buildUnwindData(address user, uint256 targetLeverage)
        private
        view
        returns (UnwindCallbackData memory cb)
    {
        Position memory pos = morpho.position(marketId, user);
        Market memory mkt = morpho.market(marketId);

        if (pos.collateral == 0) revert NoCollateral();

        uint256 existingDebt = _sharesToAssets(pos.borrowShares, mkt);
        uint256 rate = apyUSD.convertToAssets(WAD);
        uint256 totalCollateralApxUSD = uint256(pos.collateral).mulDiv(rate, WAD);
        uint256 netEquityApxUSD = totalCollateralApxUSD - existingDebt;
        uint256 currentLeverage = totalCollateralApxUSD.mulDiv(WAD, netEquityApxUSD);

        if (targetLeverage >= currentLeverage) revert LeverageMustDecrease(currentLeverage, targetLeverage);

        cb.user = user;
        cb.borrowShares = pos.borrowShares;
        cb.fullExit = targetLeverage == 0;

        if (cb.fullExit) {
            cb.debtToRepay = existingDebt;
            // Use the raw share-derived collateral amount to avoid apxUSD→apyUSD rounding.
            cb.collateralToWithdrawApyUSD = pos.collateral;
            cb.remainingCollateral = 0;
            cb.remainingDebt = 0;
        } else {
            uint256 targetDebt =
                targetLeverage <= WAD ? 0 : netEquityApxUSD.mulDiv(targetLeverage - WAD, WAD);
            cb.debtToRepay = existingDebt - targetDebt;
            // get_dx accounts for Curve fees so the swap output is guaranteed to cover the flash repayment.
            cb.collateralToWithdrawApyUSD = curvePool.get_dx(APYUSD_INDEX, APXUSD_INDEX, cb.debtToRepay);
            cb.remainingCollateral = pos.collateral - cb.collateralToWithdrawApyUSD;
            cb.remainingDebt = existingDebt - cb.debtToRepay;
        }
    }

    // -------------------------------------------------------------------------
    // Flash loan callback
    // -------------------------------------------------------------------------

    /**
     * @notice Called by Morpho mid-flash-loan.
     * @dev Two security checks before doing anything:
     *      - msg.sender must be Morpho (prevents arbitrary callers from triggering position logic)
     *      - _flashInitiator must be set (rules out external flashLoan calls targeting this contract)
     */
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external override {
        if (msg.sender != address(morpho)) revert UnauthorizedFlashLoan(msg.sender);
        if (_flashInitiator == address(0)) revert NoFlashLoanInitiator();

        bool isLoop = abi.decode(data[:32], (bool));

        if (isLoop) {
            _handleLoop(assets, data);
        } else {
            (, UnwindCallbackData memory cb) = abi.decode(data, (bool, UnwindCallbackData));
            _handleUnwind(assets, cb);
        }
    }

    function _handleLoop(uint256 flashAmount, bytes calldata data) internal {
        (, address user,) = abi.decode(data, (bool, address, uint256));

        // Deposit directly into the vault — no Curve, no fees. apyUSD.deposit() converts
        // at the live exchange rate. We get slightly fewer apyUSD than flashAmount because
        // the vault rate is > 1 once yield has accrued.
        uint256 apyUSDReceived = apyUSD.deposit(flashAmount, address(this));

        // supplyCollateral doesn't require Morpho authorization — anyone can top up anyone's collateral.
        morpho.supplyCollateral(marketParams, apyUSDReceived, user, "");

        // borrow() does require authorization. User must have called setAuthorization(address(this), true).
        morpho.borrow(marketParams, flashAmount, 0, user, address(this));

        // Contract now holds flashAmount apxUSD. Morpho pulls it back to settle the flash loan.
    }

    function _handleUnwind(uint256 debtToRepay, UnwindCallbackData memory cb) internal {
        address user = cb.user;

        // Full exit repays by shares to guarantee zero dust. A shares-to-assets rounding error
        // would otherwise leave a tiny borrow that prevents withdrawing the remaining collateral.
        if (cb.fullExit) {
            morpho.repay(marketParams, 0, cb.borrowShares, user, "");
        } else {
            morpho.repay(marketParams, debtToRepay, 0, user, "");
        }

        morpho.withdrawCollateral(marketParams, cb.collateralToWithdrawApyUSD, user, address(this));

        // get_dx in _buildUnwindData already sized the input so we get at least debtToRepay out,
        // but we also enforce the configured slippage floor as a second layer of protection.
        uint256 expectedApxUSD = curvePool.get_dy(APYUSD_INDEX, APXUSD_INDEX, cb.collateralToWithdrawApyUSD);
        uint256 minApxUSD = expectedApxUSD.mulDiv(BPS_DENOMINATOR - slippageBps, BPS_DENOMINATOR);

        // Never accept a min that's below the flash loan amount — that would leave us unable to repay.
        if (minApxUSD < debtToRepay) minApxUSD = debtToRepay;

        uint256 apxUSDReceived =
            curvePool.exchange(APYUSD_INDEX, APXUSD_INDEX, cb.collateralToWithdrawApyUSD, minApxUSD);

        // Morpho pulls debtToRepay back. Anything left over is the user's recovered equity (minus fees).
        uint256 surplus = apxUSDReceived - debtToRepay;
        if (surplus > 0) {
            apxUSD.safeTransfer(user, surplus);
        }
    }

    // -------------------------------------------------------------------------
    // Slippage configuration
    // -------------------------------------------------------------------------

    /**
     * @notice Queue a new slippage tolerance. Active after SLIPPAGE_COOLDOWN via applySlippageBps().
     * @param newBps Basis points (e.g. 50 = 0.5%). Cannot exceed MAX_SLIPPAGE_BPS.
     */
    function setSlippageBps(uint256 newBps) external restricted {
        if (newBps > MAX_SLIPPAGE_BPS) revert SlippageExceedsMax(newBps, MAX_SLIPPAGE_BPS);
        pendingSlippageBps = newBps;
        pendingSlippageEffectiveAt = block.timestamp + SLIPPAGE_COOLDOWN;
        emit SlippageBpsQueued(newBps, pendingSlippageEffectiveAt);
    }

    /// @notice Activate the pending slippage value. Restricted so the admin controls both steps.
    function applySlippageBps() external restricted {
        if (block.timestamp < pendingSlippageEffectiveAt) {
            revert SlippageCooldownNotElapsed(pendingSlippageEffectiveAt, block.timestamp);
        }
        uint256 oldBps = slippageBps;
        slippageBps = pendingSlippageBps;
        emit SlippageBpsApplied(oldBps, slippageBps);
    }

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /**
     * @notice Maximum leverage this market supports, with a safety buffer below liquidation.
     * @dev maxLev = WAD / (WAD - (lltv - LLTV_SAFETY_BUFFER))
     *      E.g. LLTV = 86%, buffer = 2% → effective = 84% → maxLev = 6.25x
     */
    function maxLeverage() public view returns (uint256) {
        return WAD.mulDiv(WAD, WAD - (marketParams.lltv - LLTV_SAFETY_BUFFER));
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev accrueInterest() must be called before this for an accurate result.
    function _sharesToAssets(uint128 borrowShares, Market memory mkt) internal pure returns (uint256) {
        if (mkt.totalBorrowShares == 0) return 0;
        return uint256(borrowShares).mulDiv(mkt.totalBorrowAssets, mkt.totalBorrowShares);
    }

    /// @dev Only used for the Looped event — not in the critical path.
    function _apxUSDToApyUSD(uint256 apxUSDAmount, uint256 rate) internal pure returns (uint256) {
        return apxUSDAmount.mulDiv(WAD, rate);
    }
}
