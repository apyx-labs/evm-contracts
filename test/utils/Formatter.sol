// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Format
 * @notice Library of utility functions for formatting values
 */
library Formatter {
    /**
     * @notice Format a uint256 value as a decimal string with specified decimals
     * @param self The uint256 value to format (in smallest unit, e.g., wei)
     * @return Decimal string representation (e.g., "1000.5" for 1000500000000000000000 with 18 decimals)
     */
    function formatDecimal(uint256 self) internal pure returns (string memory) {
        return formatDecimal(self, 18);
    }

    /**
     * @notice Format a uint256 value as a decimal string with specified decimals
     * @param self The uint256 value to format (in smallest unit, e.g., wei)
     * @param decimals The number of decimal places (e.g., 18 for tokens)
     * @return Decimal string representation (e.g., "1000.5" for 1000500000000000000000 with 18 decimals)
     */
    function formatDecimal(uint256 self, uint8 decimals) internal pure returns (string memory) {
        if (self == 0) {
            return "0";
        }

        // Calculate divisor (10^decimals)
        uint256 divisor = 10 ** decimals;

        // Split into integer and fractional parts
        uint256 integerPart = self / divisor;
        uint256 fractionalPart = self % divisor;

        // Convert integer part to string
        string memory integerStr = Strings.toString(integerPart);

        // If fractional part is zero, return just the integer part
        if (fractionalPart == 0) {
            return integerStr;
        }

        // Convert fractional part to string, padding with leading zeros if needed
        string memory fractionalStr = Strings.toString(fractionalPart);

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
