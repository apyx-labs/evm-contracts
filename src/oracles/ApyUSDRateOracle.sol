// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {EInvalidAmount} from "../errors/InvalidAmount.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";

/// @title ApyUSDRateOracle
/// @notice Provides the exchange rate of apyUSD for a Curve Stableswap-NG pool.
/// @dev Reads `convertToAssets(1e18)` from the apyUSD ERC-4626 vault and multiplies
///      by a configurable `adjustment`. Called by the Curve pool via staticcall to `rate()`.
///      The full call chain is read-only; standard ERC-4626 vaults satisfy this requirement.
contract ApyUSDRateOracle is
    Initializable,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    EInvalidAmount,
    EInvalidAddress
{
    // ========================================
    // Constants
    // ========================================

    /// @notice Minimum allowed adjustment (90% — discounts apyUSD by up to 10%)
    uint256 public constant MIN_ADJUSTMENT = 0.90e18;

    /// @notice Maximum allowed adjustment (110% — premiums apyUSD by up to 10%)
    uint256 public constant MAX_ADJUSTMENT = 1.10e18;

    // ========================================
    // Storage (ERC-7201)
    // ========================================

    /// @custom:storage-location erc7201:apyx.storage.ApyUSDRateOracle
    struct ApyUSDRateOracleStorage {
        uint256 adjustment;
        address apyUSD;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.ApyUSDRateOracle")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x7c3fd745b6b17d3e08ed287c3401ed4dbb5b9270e485a2fb2e22ca2d91e6e000;

    function _getStorage() private pure returns (ApyUSDRateOracleStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    // ========================================
    // Events
    // ========================================

    event AdjustmentUpdated(uint256 oldAdjustment, uint256 newAdjustment);

    // ========================================
    // Constructor
    // ========================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ========================================
    // Initializer
    // ========================================

    /// @notice Initializes the oracle with neutral adjustment (1e18) and the apyUSD vault address.
    /// @param initialAuthority The AccessManager address.
    /// @param apyUSD_ The apyUSD ERC-4626 vault address.
    function initialize(address initialAuthority, address apyUSD_) external initializer {
        if (apyUSD_ == address(0)) revert InvalidAddress("apyUSD");
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");

        __AccessManaged_init(initialAuthority);

        ApyUSDRateOracleStorage storage $ = _getStorage();
        $.apyUSD = apyUSD_;
        $.adjustment = 1e18;
    }

    // ========================================
    // View Functions
    // ========================================

    /// @notice Returns the current rate fed to the Curve pool.
    /// @return The apyUSD redemption rate multiplied by adjustment, in 1e18 precision.
    function rate() external view returns (uint256) {
        ApyUSDRateOracleStorage storage $ = _getStorage();
        uint256 vaultRate = IERC4626($.apyUSD).convertToAssets(1e18);
        return vaultRate * $.adjustment / 1e18;
    }

    /// @notice Returns the current adjustment value.
    /// @return The current adjustment in 1e18 precision (1e18 = neutral).
    function adjustment() external view returns (uint256) {
        return _getStorage().adjustment;
    }

    // ========================================
    // Admin Functions
    // ========================================

    /// @notice Sets the adjustment value. Must be within [MIN_ADJUSTMENT, MAX_ADJUSTMENT].
    /// @param newAdjustment New adjustment value in 1e18 precision.
    function setAdjustment(uint256 newAdjustment) external restricted {
        if (newAdjustment < MIN_ADJUSTMENT) revert InvalidAmount("newAdjustment", newAdjustment);
        if (newAdjustment > MAX_ADJUSTMENT) revert InvalidAmount("newAdjustment", newAdjustment);

        ApyUSDRateOracleStorage storage $ = _getStorage();
        uint256 oldAdjustment = $.adjustment;
        $.adjustment = newAdjustment;

        emit AdjustmentUpdated(oldAdjustment, newAdjustment);
    }

    // ========================================
    // UUPS
    // ========================================

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
