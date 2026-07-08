// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IAddressList} from "./IAddressList.sol";

/// @title IDenyListed
/// @notice Minimal surface for reading an ERC-20's deny-list reference.
interface IDenyListed {
    function denyList() external view returns (IAddressList);
}
