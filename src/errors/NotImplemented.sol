// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title ENotImplemented
 * @notice Interface for the NotImplemented error
 */
interface ENotImplemented {
    /**
     * @notice Error thrown when a function is intentionally not implemented.
     * @dev Used for interface compliance stubs — the function signature exists to satisfy
     *      an inherited interface but the operation is not supported by this contract.
     */
    error NotImplemented();
}
