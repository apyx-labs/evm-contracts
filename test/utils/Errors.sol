// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {EInvalidAddress} from "../../src/errors/InvalidAddress.sol";
import {EInvalidAmount} from "../../src/errors/InvalidAmount.sol";
import {EInsufficientBalance} from "../../src/errors/InsufficientBalance.sol";
import {ENotSupported} from "../../src/errors/NotSupported.sol";
import {EInvalidCaller} from "../../src/errors/InvalidCaller.sol";
import {EDenied} from "../../src/errors/Denied.sol";
import {EAddressNotSet} from "../../src/errors/AddressNotSet.sol";

/**
 * @title Errors
 * @notice Helper library for encoding error selectors in tests
 */
library Errors {
    function invalidAddress(string memory param) external pure returns (bytes memory) {
        return abi.encodeWithSelector(EInvalidAddress.InvalidAddress.selector, param);
    }

    function invalidAmount(string memory param, uint256 amount) external pure returns (bytes memory) {
        return abi.encodeWithSelector(EInvalidAmount.InvalidAmount.selector, param, amount);
    }

    function insufficientBalance(address owner, uint256 balance, uint256 amount) external pure returns (bytes memory) {
        return abi.encodeWithSelector(EInsufficientBalance.InsufficientBalance.selector, owner, balance, amount);
    }

    function notSupported() external pure returns (bytes4) {
        return ENotSupported.NotSupported.selector;
    }

    function invalidCaller() external pure returns (bytes4) {
        return EInvalidCaller.InvalidCaller.selector;
    }

    function denied(address denied_) external pure returns (bytes memory) {
        return abi.encodeWithSelector(EDenied.Denied.selector, denied_);
    }

    function addressNotSet(string memory param) external pure returns (bytes memory) {
        return abi.encodeWithSelector(EAddressNotSet.AddressNotSet.selector, param);
    }
}
