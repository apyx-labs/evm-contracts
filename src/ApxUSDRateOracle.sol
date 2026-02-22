// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {EInvalidAmount} from "./errors/InvalidAmount.sol";

/// @title ApxUSDRateOracle
/// @notice Provides the exchange rate of apxUSD relative to USDC for Curve Stableswap-NG pools.
/// @dev The rate represents how many USDC 1 apxUSD is worth based on the off-chain collateral
///      backing apxUSD, expressed as a uint256 with 1e18 precision.
///      - 1e18 = 1 apxUSD is worth 1 USDC
///      - 1.02e18 = 1 apxUSD is worth 1.02 USDC
///      Called by the Curve pool via staticcall to `rate()`.
contract ApxUSDRateOracle is Initializable, AccessManagedUpgradeable, UUPSUpgradeable, EInvalidAmount {
    /// @custom:storage-location erc7201:apyx.storage.ApxUSDRateOracle
    struct ApxUSDRateOracleStorage {
        uint256 rate;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.ApxUSDRateOracle")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x27bd078109e9748e45a8094381d0fb92b7b8cc1084b35874a4d9e8826ec4f100;

    function _getStorage() private pure returns (ApxUSDRateOracleStorage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    event RateUpdated(uint256 oldRate, uint256 newRate);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the oracle with a default rate of 1e18 (1:1 peg).
    /// @param initialAuthority The address of the authority that can set the rate.
    function initialize(address initialAuthority) external initializer {
        __AccessManaged_init(initialAuthority);

        ApxUSDRateOracleStorage storage $ = _getStorage();
        $.rate = 1e18;
    }

    /// @notice Returns the current rate of apxUSD relative to USDC.
    /// @return The current rate in 1e18 precision.
    function rate() external view returns (uint256) {
        ApxUSDRateOracleStorage storage $ = _getStorage();
        return $.rate;
    }

    /// @notice Sets the rate of apxUSD relative to USDC.
    /// @param newRate The new rate in 1e18 precision (must be > 0).
    function setRate(uint256 newRate) external restricted {
        if (newRate == 0) revert InvalidAmount("newRate", newRate);
        ApxUSDRateOracleStorage storage $ = _getStorage();

        uint256 oldRate = $.rate;
        $.rate = newRate;

        emit RateUpdated(oldRate, newRate);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
