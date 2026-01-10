// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";
import {VmExt} from "../../utils/VmExt.sol";
import {Vm} from "forge-std/src/Vm.sol";

/**
 * @title MinterTest
 * @notice Base test contract for MinterV0 tests with shared setup and helper functions
 */
abstract contract MinterTest is BaseTest {
    using VmExt for Vm;

    // Fusaka upgrade gas limit: 2^24 = 16,777,216 gas
    uint256 constant FUSAKA_GAS_LIMIT = 2 ** 24;
    uint256 constant REASONABLE_GAS_LIMIT = 5_000_000;
    uint48 constant LARGE_NUM_MINTS = 256;

    /**
     * @notice Creates a mint order with default time window
     * @param beneficiary Address that will receive minted tokens
     * @param nonce Current nonce for the beneficiary
     * @param amount Amount of tokens to mint
     * @return order The created mint order
     */
    function _createOrder(address beneficiary, uint48 nonce, uint208 amount)
        internal
        view
        returns (IMinterV0.Order memory)
    {
        uint256 currentTimestamp = vm.clone(block.timestamp);

        return IMinterV0.Order({
            beneficiary: beneficiary,
            notBefore: uint48(currentTimestamp),
            notAfter: uint48(currentTimestamp + 24 hours), // Long enough to not expire during tests
            nonce: nonce,
            amount: amount
        });
    }

    /**
     * @notice Signs a mint order with EIP-712
     * @param order The mint order to sign
     * @param privateKey Private key to sign with
     * @return signature The EIP-712 signature
     */
    function _signOrder(IMinterV0.Order memory order, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = minterV0.hashOrder(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function cancelMint(bytes32 operationId) internal {
        vm.prank(minterGuardian);
        minterV0.cancelMint(operationId);
    }
}
