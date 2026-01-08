// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/src/Test.sol";
import {Vm} from "forge-std/src/Vm.sol";

import {Formatter} from "../utils/Formatter.sol";
import {ReportBase} from "./ReportBase.sol";
import {VestingTest} from "../contracts/Vesting/BaseTest.sol";
import {VmExt} from "../utils/VmExt.sol";
import {IVesting} from "../../src/interfaces/IVesting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title VestingReport
 * @notice Test contract that generates CSV reports for vesting contract data
 * @dev Tests vesting contract and writes reports showing balance, unvested, and vested amounts over time
 *
 * Usage:
 *   forge test --match-contract VestingReport -vv
 *
 * The test will generate a CSV file at out/reports/vesting_report.csv
 */
contract VestingReport is ReportBase, VestingTest {
    using VmExt for Vm;
    using Formatter for uint256;

    /// @notice CSV filename for vesting report
    string public constant VESTING_REPORT_FILENAME = "vesting_report.csv";

    /// @notice Amount of yield to deposit for testing
    uint256 public constant TEST_YIELD_AMOUNT = 1000e18;

    /// @notice Time increment for iterations (5 minutes)
    uint256 public constant TIME_INCREMENT = 5 minutes;

    function setUp() public override(ReportBase, VestingTest) {
        VestingTest.setUp();
        ReportBase.setUp();
    }

    /**
     * @notice Test that deposits yield and iterates through time in 5 minute increments
     * @dev Writes CSV with timestamp, balance, vested, and unvested amounts at each interval
     *      Iterates from current time (after deposit) through the full vesting period
     */
    function test_Report_Vesting_OverTime() public {
        // Deposit initial yield
        deal(address(apxUSD), yieldDistributor, TEST_YIELD_AMOUNT);
        depositYield(yieldDistributor, TEST_YIELD_AMOUNT);

        // Get initial timestamp (after deposit) and vesting period
        uint256 currentTimestamp = vm.clone(block.timestamp);
        uint256 vestingPeriod = vesting.vestingPeriod();

        // Calculate number of iterations (from start to end in 5 minute increments)
        uint256 numIterations = (vestingPeriod / TIME_INCREMENT) + 1; // +1 for initial state

        // Collect data points at each time increment
        // We'll build the rows dynamically since we might hit the end early
        string[][] memory rows = new string[][](numIterations + 1);
        rows[0] = _getReportRow(currentTimestamp);

        // Iterate through time in 5 minute increments from start to end
        for (uint256 i = 1; i <= numIterations; i++) {
            currentTimestamp += TIME_INCREMENT;
            vm.warp(currentTimestamp);
            rows[i] = _getReportRow(currentTimestamp);
        }
        writeCSV("simple_vesting.csv", _headers(), rows);
    }

    function test_Report_Vesting_MultipleDeposits() public {
        // Get initial timestamp (after deposit) and vesting period
        uint256 currentTimestamp = vm.clone(block.timestamp);
        uint256 vestingPeriod = vesting.vestingPeriod();

        // Calculate number of iterations (from start to end in 5 minute increments)
        uint256 numDeposits = 3;
        uint256 numIterations = vestingPeriod / TIME_INCREMENT;

        // Collect data points at each time increment
        // We'll build the rows dynamically since we might hit the end early
        string[][] memory rows = new string[][](
            numDeposits * numIterations + 1 // +1 for initial state
        );
        rows[0] = _getReportRow(currentTimestamp);

        for (uint256 j = 0; j < numDeposits; j++) {
            // Deposit yield
            deal(address(apxUSD), yieldDistributor, TEST_YIELD_AMOUNT);
            depositYield(yieldDistributor, TEST_YIELD_AMOUNT);

            // Iterate through time in 5 minute increments from start to end
            for (uint256 i = 1; i <= numIterations; i++) {
                currentTimestamp += TIME_INCREMENT;
                vm.warp(currentTimestamp);
                rows[j * numIterations + i] = _getReportRow(currentTimestamp);
            }
        }
        writeCSV("multiple_deposits_vesting.csv", _headers(), rows);
    }

    function test_Report_Vesting_DepositMidVesting() public {
        // Deposit initial yield
        deal(address(apxUSD), yieldDistributor, TEST_YIELD_AMOUNT);
        depositYield(yieldDistributor, TEST_YIELD_AMOUNT);

        // Get initial timestamp (after deposit) and vesting period
        uint256 currentTimestamp = vm.clone(block.timestamp);
        uint256 vestingPeriod = vesting.vestingPeriod();

        // Calculate number of iterations (from start to end in 5 minute increments)
        uint256 numIterations = (vestingPeriod / TIME_INCREMENT) + 1; // +1 for initial state

        string[][] memory rows = new string[][](numIterations + 1);
        rows[0] = _getReportRow(currentTimestamp);

        // Iterate through time in 5 minute increments from start to end
        for (uint256 i = 1; i <= numIterations; i++) {
            if (i == numIterations / 2) {
                // Deposit additional yield
                deal(address(apxUSD), yieldDistributor, TEST_YIELD_AMOUNT);
                depositYield(yieldDistributor, TEST_YIELD_AMOUNT);
            }

            currentTimestamp += TIME_INCREMENT;
            vm.warp(currentTimestamp);
            rows[i] = _getReportRow(currentTimestamp);
        }
        writeCSV("deposit_mid_vesting.csv", _headers(), rows);
    }

    function _headers() internal pure returns (string[] memory) {
        string[] memory headers = new string[](4);
        headers[0] = "Timestamp";
        headers[1] = "Balance";
        headers[2] = "Unvested";
        headers[3] = "Vested";
        return headers;
    }

    /**
     * @notice Get a report row with current vesting state
     * @param timestamp Current timestamp for the row
     * @return Array of string values for the CSV row
     */
    function _getReportRow(uint256 timestamp) internal view returns (string[] memory) {
        address assetAddress = vesting.asset();
        IERC20Metadata asset = IERC20Metadata(assetAddress);

        uint256 balance = asset.balanceOf(address(vesting));
        uint256 vested = vesting.vestedAmount();
        uint256 unvested = vesting.unvestedAmount();

        string[] memory row = new string[](4);
        row[0] = vm.toString(timestamp);
        row[1] = balance.formatDecimal();
        row[2] = unvested.formatDecimal();
        row[3] = vested.formatDecimal();

        return row;
    }
}
