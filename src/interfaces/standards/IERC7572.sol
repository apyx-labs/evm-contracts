// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IERC7572
 * @notice Contract-level metadata URI (EIP-7572).
 * @dev See https://eips.ethereum.org/EIPS/eip-7572
 */
interface IERC7572 {
    /// @notice Emitted when the contract-level metadata URI changes.
    event ContractURIUpdated();

    /// @notice Returns the contract-level metadata URI.
    function contractURI() external view returns (string memory);
}
