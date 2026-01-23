// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVesting} from "./interfaces/IVesting.sol";

/**
 * @title LinearVestV0
 * @notice Contract that receives yield deposits and vests them linearly over a configurable period
 * @dev Allows yield distributors to deposit yield, which vests linearly over time.
 *      Only vault contract can transfer vested yield. New deposits reset the vesting period.
 *
 * Features:
 * - Linear vesting over configurable period
 * - Vesting period resets on new deposits (adds to existing unvested amount)
 * - Only vault can transfer vested yield
 * - Access control via AccessManager
 */
contract LinearVestV0 is AccessManaged, IVesting {
    using SafeERC20 for IERC20;

    // ========================================
    // State Variables
    // ========================================

    /// @notice The asset token (apxUSD) held in vesting
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IERC20 public immutable asset;

    /// @notice Total amount currently vesting
    uint256 public vestingAmount;

    /// @notice Total amount that has been fully vested but not yet transferred to the beneficiary
    uint256 public fullyVestedAmount;

    /// @notice Timestamp of the last deposit (when vesting period was reset)
    uint256 public lastDepositTimestamp;

    /// @notice Timestamp of the last transfer (when vested yield was transferred to the beneficiary)
    uint256 public lastTransferTimestamp;

    /// @notice Vesting period in seconds
    uint256 public vestingPeriod;

    /// @notice Beneficiary contract address (authorized for transfers)
    address public beneficiary;

    // ========================================
    // Modifiers
    // ========================================

    /**
     * @notice Ensures only vault contract can call transfer functions
     * @dev This is only applied to the transferVestedYield function, so it is more efficient to inline
     */
    // forge-lint: disable-next-line(unwrapped-modifier-logic)
    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert UnauthorizedTransfer();
        _;
    }

    // ========================================
    // Constructor
    // ========================================

    /**
     * @notice Initializes the LinearVestV0 contract
     * @param _asset Address of the asset token (apxUSD)
     * @param _authority Address of the AccessManager contract
     * @param _beneficiary Address of the beneficiary contract
     * @param _vestingPeriod Initial vesting period in seconds
     */
    constructor(address _asset, address _authority, address _beneficiary, uint256 _vestingPeriod)
        AccessManaged(_authority)
    {
        if (_asset == address(0)) revert InvalidAddress("asset");
        if (_authority == address(0)) revert InvalidAddress("authority");
        if (_beneficiary == address(0)) revert InvalidAddress("beneficiary");
        if (_vestingPeriod == 0) revert InvalidAmount("vestingPeriod", _vestingPeriod);

        asset = IERC20(_asset);
        beneficiary = _beneficiary;
        vestingPeriod = _vestingPeriod;
    }

    // ========================================
    // View Functions
    // ========================================

    /**
     * @notice Returns the amount of yield that has vested and is available, including
     *         fully vested yield. This is used to calculate vested amounts including
     *         fully vested yield.
     * @return Amount of vested yield including fully vested yield
     */
    function vestedAmount() external view override returns (uint256) {
        return fullyVestedAmount + _vestedAmount();
    }

    /**
     * @notice Returns the amount of yield that has vested and is available, excluding
     *         fully vested yield. This is used to calculate vested amounts without
     *         double counting the fully vested yield.
     * @return Amount of vested yield excluding fully vested yield
     */
    function _vestedAmount() internal view returns (uint256) {
        // slither-disable-next-line incorrect-equality
        if (vestingAmount == 0) return 0;

        uint256 timeSinceLastDeposit;
        unchecked {
            timeSinceLastDeposit = block.timestamp - lastDepositTimestamp;
        }

        uint256 timeSinceLastTransfer;
        unchecked {
            timeSinceLastTransfer = block.timestamp - lastTransferTimestamp;
        }

        // slither-disable-next-line timestamp
        if (timeSinceLastDeposit >= vestingPeriod) {
            return vestingAmount; // Fully vested
        }
        uint256 timeBetweenDepositAndTransfer = lastTransferTimestamp - lastDepositTimestamp;
        uint256 originalVestingAmount = vestingAmount * vestingPeriod / (vestingPeriod - timeBetweenDepositAndTransfer);

        return (originalVestingAmount * timeSinceLastTransfer) / vestingPeriod;
    }

    /**
     * @notice Returns the amount of yield that is still vesting
     * @return Amount of unvested yield
     */
    function unvestedAmount() external view override returns (uint256) {
        return _unvestedAmount(_vestedAmount());
    }

    /**
     * @notice Returns the amount of yield that is still vesting
     * @dev Internal function to calculate unvested amount without recalculating vested amount
     * @param amount Amount of vested yield
     * @return Amount of unvested yield
     */
    function _unvestedAmount(uint256 amount) internal view returns (uint256) {
        return vestingAmount - amount;
    }

    // ========================================
    // State-Changing Functions
    // ========================================

    /**
     * @notice Deposits yield into the vesting contract
     * @dev Transfers out any vested yield before resetting the vesting period.
     *      Resets the vesting period by adding new deposit to existing unvested amount.
     * @param amount Amount of yield to depositinternal
     */
    function depositYield(uint256 amount) external override restricted {
        if (amount == 0) revert InvalidAmount("amount", amount);

        // Calculate unvested amount BEFORE transferring
        uint256 vested = _vestedAmount();
        uint256 unvested = _unvestedAmount(vested);

        // Add new amount to fully vested and unvested amount
        fullyVestedAmount += vested;
        vestingAmount = unvested + amount;

        // Update timestamps
        lastDepositTimestamp = block.timestamp;
        lastTransferTimestamp = block.timestamp;

        // Transfer assets from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit YieldDeposited(msg.sender, amount);
    }

    /**
     * @notice Transfers all vested yield to the vault
     * @dev Only callable by vault contract. No-op if no vested yield available.
     */
    function transferVestedYield() external override onlyBeneficiary {
        uint256 vested = _vestedAmount();
        vestingAmount -= vested;

        uint256 transferAmount = vested + fullyVestedAmount;

        fullyVestedAmount = 0;
        lastTransferTimestamp = block.timestamp;

        // No-op if no vested yield available
        // slither-disable-next-line incorrect-equality,timestamp
        if (transferAmount == 0) return;

        // Transfer vested yield to beneficiary
        asset.safeTransfer(beneficiary, transferAmount);
        emit VestedYieldTransferred(beneficiary, transferAmount);
    }

    /**
     * @notice Sets the vesting period
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newPeriod New vesting period in seconds
     */
    function setVestingPeriod(uint256 newPeriod) external override restricted {
        if (newPeriod == 0) revert InvalidAmount("vestingPeriod", newPeriod);

        uint256 oldPeriod = vestingPeriod;
        vestingPeriod = newPeriod;

        emit VestingPeriodUpdated(oldPeriod, newPeriod);
    }

    /**
     * @notice Sets the beneficiary address. This is used when initializing the vesting contract,
     *         to set the beneficiary address and when migrating to a new vesting contract.
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newBeneficiary New beneficiary contract address
     */
    function setBeneficiary(address newBeneficiary) external override restricted {
        if (newBeneficiary == address(0)) revert InvalidAddress("beneficiary");

        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }
}
