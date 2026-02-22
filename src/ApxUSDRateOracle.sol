// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";

/// @title ApxUSDRateOracle
/// @notice Provides the exchange rate of apxUSD relative to USDC for Curve Stableswap-NG pools.
/// @dev The rate is manually set by an authorized admin and represents how many USDC 1 apxUSD is worth,
///      expressed as a uint256 with 1e18 precision.
///      - 1e18 = 1 apxUSD is worth 1 USDC
///      - 1.02e18 = 1 apxUSD is worth 1.02 USDC
///      Called by the Curve pool via staticcall to `rate()`.
contract ApxUSDRateOracle is Initializable, AccessManagedUpgradeable, UUPSUpgradeable {
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

    event RateUpdated(uint256 newRate, address indexed updatedBy);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the oracle with a default rate of 1e18 (1:1 peg).
    /// @param accessManager_ The address of the AccessManager contract.
    function initialize(address accessManager_) external initializer {
        __AccessManaged_init(accessManager_);

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
        require(newRate > 0, "Rate must be > 0");
        ApxUSDRateOracleStorage storage $ = _getStorage();
        $.rate = newRate;
        emit RateUpdated(newRate, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override restricted {}
}
