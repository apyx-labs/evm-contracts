// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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
     * @dev This is only applied to the pullVestedYield function, so it is more efficient to inline
     */
    // forge-lint: disable-next-item(unwrapped-modifier-logic)
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
     * @inheritdoc IVesting
     */
    function vestingPeriodStart() public view override returns (uint256) {
        return lastDepositTimestamp;
    }

    /**
     * @inheritdoc IVesting
     */
    function vestingPeriodEnd() public view override returns (uint256) {
        return lastDepositTimestamp + vestingPeriod;
    }

    /**
     * @inheritdoc IVesting
     */
    function vestingPeriodRemaining() public view override returns (uint256) {
        // slither-disable-next-line timestamp
        if (block.timestamp > vestingPeriodEnd()) {
            return 0;
        }
        return vestingPeriodEnd() - block.timestamp;
    }

    /**
     * @inheritdoc IVesting
     */
    function vestedAmount() public view override returns (uint256) {
        return fullyVestedAmount + newlyVestedAmount();
    }

    /**
     * @inheritdoc IVesting
     */
    function newlyVestedAmount() public view override returns (uint256) {
        // slither-disable-next-line incorrect-equality
        if (vestingAmount == 0) return 0;

        uint256 _vestingPeriodEnd = vestingPeriodEnd();
        if (lastTransferTimestamp >= _vestingPeriodEnd) return 0;

        uint256 newlyVestedPeriod;
        unchecked {
            newlyVestedPeriod = Math.min(block.timestamp, _vestingPeriodEnd) - lastTransferTimestamp;
        }

        return Math.mulDiv(vestingAmount, newlyVestedPeriod, vestingPeriod, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IVesting
     */
    function unvestedAmount() public view override returns (uint256) {
        uint256 periodRemaining = vestingPeriodRemaining();

        // slither-disable-next-line incorrect-equality
        if (periodRemaining == 0) return 0;

        return Math.mulDiv(vestingAmount, periodRemaining, vestingPeriod, Math.Rounding.Ceil);
    }

    // ========================================
    // State-Changing Functions
    // ========================================

    /**
     * @inheritdoc IVesting
     */
    function depositYield(uint256 amount) external override restricted {
        if (amount == 0) revert InvalidAmount("amount", amount);

        // Add new amount to fully vested and unvested amount
        fullyVestedAmount += newlyVestedAmount();
        vestingAmount = unvestedAmount() + amount;

        // Update timestamps
        lastDepositTimestamp = block.timestamp;
        lastTransferTimestamp = block.timestamp;

        // Transfer assets from caller
        asset.safeTransferFrom(msg.sender, address(this), amount);
        emit YieldDeposited(msg.sender, amount);
    }

    /**
     * @inheritdoc IVesting
     */
    function pullVestedYield() external override onlyBeneficiary {
        uint256 transferAmount = vestedAmount();

        fullyVestedAmount = 0;
        lastTransferTimestamp = block.timestamp;

        // No-op if no vested yield available
        // slither-disable-next-line incorrect-equality,timestamp
        if (transferAmount == 0) return;

        // Transfer vested yield to beneficiary
        asset.safeTransfer(beneficiary, transferAmount);
        emit VestedYieldTransferred(beneficiary, transferAmount);
    }

    // ========================================
    // Admin Functions
    // ========================================

    /**
     * @inheritdoc IVesting
     */
    function setVestingPeriod(uint256 newPeriod) external override restricted {
        if (newPeriod == 0) revert InvalidAmount("vestingPeriod", newPeriod);

        uint256 newlyVested = newlyVestedAmount();
        fullyVestedAmount += newlyVested;
        vestingAmount -= newlyVested;

        lastDepositTimestamp = block.timestamp;
        lastTransferTimestamp = block.timestamp;

        uint256 oldPeriod = vestingPeriod;
        vestingPeriod = newPeriod;

        emit VestingPeriodUpdated(oldPeriod, newPeriod);
    }

    /**
     * @inheritdoc IVesting
     */
    function setBeneficiary(address newBeneficiary) external override restricted {
        if (newBeneficiary == address(0)) revert InvalidAddress("beneficiary");

        address oldBeneficiary = beneficiary;
        beneficiary = newBeneficiary;
        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }
}
