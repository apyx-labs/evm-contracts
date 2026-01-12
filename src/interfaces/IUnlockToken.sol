// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ICommitToken} from "./ICommitToken.sol";

/**
 * @title IUnlockToken
 * @notice Interface for UnlockToken contract that allows a vault to act as an operator
 */
interface IUnlockToken is ICommitToken {
    /**
     * @notice Returns the vault address that can act as an operator
     * @return The vault address (immutable, set at construction)
     */
    function vault() external view returns (address);
}

