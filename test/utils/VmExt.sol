// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Vm} from "forge-std/src/Vm.sol";

/**
 * @title VmExt
 * @notice Library of utility functions extending the Vm cheatcode interface
 * @dev Provides reusable helper functions for testing
 */
library VmExt {
    /**
     * @notice Clone a uint256 value to avoid state errors when warping through time
     * @dev This is needed to copy the value of block.timestamp to a uint256 variable
     *      to avoid weird state errors when warping through time.
     * @param vm The Vm cheatcode interface (assumed to be available as a global variable in tests)
     * @param value The value to clone
     * @return A new uint256 with the same value
     */
    function clone(Vm vm, uint256 value) internal pure returns (uint256) {
        return vm.parseUint(vm.toString(value));
    }
}
