// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/src/Test.sol";

/**
 * @title ReportBase
 * @notice Base contract for report tests with CSV writing utilities
 * @dev Provides helper functions for generating CSV reports in test files
 */
abstract contract ReportBase is Test {
    /// @notice Base output directory for reports (relative to project root)
    string public constant REPORT_OUTPUT_DIR = "reports";

    /**
     * @notice Set up the reports directory
     * @dev Creates the out/reports directory if it doesn't exist by writing a marker file
     */
    function setUp() public virtual {
        ensureReportsDirectory();
    }

    /**
     * @notice Ensure the reports directory exists
     * @dev Creates the directory by writing a temporary marker file
     */
    function ensureReportsDirectory() internal {
        string memory root = vm.projectRoot();
        string memory markerPath = string.concat(root, "/", REPORT_OUTPUT_DIR, "/.gitkeep");

        // Try to write a marker file to create the directory structure
        // If the directory already exists, this will just update the marker file
        try vm.writeFile(markerPath, "") {
        // Success - directory exists or was created
        }
            catch {
            // If write fails, the directory structure might not be creatable
            // This is okay - we'll let the actual file write handle the error
        }
    }

    /**
     * @notice Write CSV file with header and single row
     * @param filename Name of the CSV file (e.g., "vesting_report.csv")
     * @param headers Array of header column names
     */
    function writeCSVHeaders(string memory filename, string[] memory headers) internal {
        string memory path = getReportPath(filename);

        // Build header row
        string memory headerRow = buildCSVRow(headers);

        // Write to file (will create if doesn't exist, overwrite if exists)
        vm.writeFile(path, headerRow);
    }

    /**
     * @notice Append a row to an existing CSV file
     * @param filename Name of the CSV file
     * @param values Array of values for the row
     */
    function appendCSVRow(string memory filename, string[] memory values) internal {
        string memory path = getReportPath(filename);

        // Check if file exists
        bool fileExists = vm.exists(path);

        // Build row
        string memory row = buildCSVRow(values);
        string memory rowWithNewline = string.concat(row, "\n");

        if (fileExists) {
            // Read existing content and append
            string memory existingContent = vm.readFile(path);
            string memory newContent = string.concat(existingContent, rowWithNewline);
            vm.writeFile(path, newContent);
        } else {
            // Create new file with just the row
            vm.writeFile(path, rowWithNewline);
        }

        console2.log("Appended row to:", path);
    }

    /**
     * @notice Write CSV file with header and multiple rows
     * @param filename Name of the CSV file
     * @param headers Array of header column names
     * @param rows Array of rows, where each row is an array of string values
     */
    function writeCSV(string memory filename, string[] memory headers, string[][] memory rows) internal {
        string memory path = getReportPath(filename);

        // Build header row
        string memory headerRow = buildCSVRow(headers);
        string memory csvContent = string.concat(headerRow, "\n");

        // Build all data rows
        for (uint256 i = 0; i < rows.length; i++) {
            require(rows[i].length == headers.length, "ReportBase: row length mismatch with headers");
            string memory row = buildCSVRow(rows[i]);
            csvContent = string.concat(csvContent, row, "\n");
        }

        // Write to file
        vm.writeFile(path, csvContent);

        console2.log("CSV written to:", path);
        console2.log(csvContent);
    }

    /**
     * @notice Build a CSV row from an array of values
     * @param values Array of string values
     * @return CSV-formatted row string
     */
    function buildCSVRow(string[] memory values) internal pure returns (string memory) {
        if (values.length == 0) {
            return "";
        }

        string memory row = values[0];

        for (uint256 i = 1; i < values.length; i++) {
            row = string.concat(row, ",", values[i]);
        }

        return row;
    }

    /**
     * @notice Get the full path for a report file
     * @param filename Name of the file
     * @return Full path string
     */
    function getReportPath(string memory filename) internal view returns (string memory) {
        string memory root = vm.projectRoot();
        return string.concat(root, "/", REPORT_OUTPUT_DIR, "/", filename);
    }

    /**
     * @notice Format a uint256 value as a decimal string with specified decimals
     * @param value The uint256 value to format (in smallest unit, e.g., wei)
     * @param decimals The number of decimal places (e.g., 18 for tokens)
     * @return Decimal string representation (e.g., "1000.5" for 1000500000000000000000 with 18 decimals)
     */
    function formatDecimalString(uint256 value, uint8 decimals) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        // Calculate divisor (10^decimals)
        uint256 divisor = 10 ** decimals;

        // Split into integer and fractional parts
        uint256 integerPart = value / divisor;
        uint256 fractionalPart = value % divisor;

        // Convert integer part to string
        string memory integerStr = vm.toString(integerPart);

        // If fractional part is zero, return just the integer part
        if (fractionalPart == 0) {
            return integerStr;
        }

        // Convert fractional part to string, padding with leading zeros if needed
        string memory fractionalStr = vm.toString(fractionalPart);

        // Pad fractional part with leading zeros to match decimals
        uint256 fractionalDigits = 0;
        uint256 temp = fractionalPart;
        while (temp != 0) {
            fractionalDigits++;
            temp /= 10;
        }

        // Build fractional string with proper padding
        string memory paddedFractional = fractionalStr;
        if (fractionalDigits < decimals) {
            // Add leading zeros
            bytes memory zeros = new bytes(decimals - fractionalDigits);
            for (uint256 i = 0; i < zeros.length; i++) {
                zeros[i] = "0";
            }
            paddedFractional = string.concat(string(zeros), fractionalStr);
        }

        // Remove trailing zeros from fractional part
        bytes memory fractionalBytes = bytes(paddedFractional);
        uint256 trailingZeros = 0;
        for (uint256 i = fractionalBytes.length; i > 0; i--) {
            if (fractionalBytes[i - 1] == "0") {
                trailingZeros++;
            } else {
                break;
            }
        }

        // If all fractional digits are zeros, return just integer part
        if (trailingZeros == fractionalBytes.length) {
            return integerStr;
        }

        // Trim trailing zeros
        uint256 fractionalLength = fractionalBytes.length - trailingZeros;
        bytes memory trimmedFractional = new bytes(fractionalLength);
        for (uint256 i = 0; i < fractionalLength; i++) {
            trimmedFractional[i] = fractionalBytes[i];
        }

        // Combine integer and fractional parts
        return string.concat(integerStr, ".", string(trimmedFractional));
    }
}
