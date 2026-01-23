// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {MinterTest} from "./BaseTest.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";

/**
 * @title MinterV0 Order Validation Tests
 * @notice Comprehensive tests for MinterV0 order validation including:
 *   - Signature validation
 *   - Nonce validation
 *   - Time window validation (notBefore, notAfter)
 *   - Amount validation
 *   - Signature malleability protection
 */
contract MinterV0_OrderValidationTest is MinterTest {
    function test_ValidateOrder_WithValidTimeWindow() public view {
        // Create order with valid time window
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp - 1 hours),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should validate successfully (no revert)
        minterV0.validateOrder(order, signature);
    }

    function test_IsOrderValid_WithValidTimeWindow() public view {
        // Create order with valid time window
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp - 1 hours),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should return true for valid order
        bool isValid = minterV0.isOrderValid(order, signature);
        assertTrue(isValid);
    }

    function test_IsOrderValid_WithInvalidOrder() public view {
        // Create order with notBefore in the future (invalid)
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp + 1 hours),
            notAfter: uint48(block.timestamp + 2 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should return false for invalid order
        bool isValid = minterV0.isOrderValid(order, signature);
        assertFalse(isValid);
    }

    function test_RevertWhen_ValidateOrderNotBeforeFuture() public {
        // Create order with notBefore in the future
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp + 1 hours),
            notAfter: uint48(block.timestamp + 2 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should revert with OrderNotYetValid
        vm.expectRevert(IMinterV0.OrderNotYetValid.selector);
        minterV0.validateOrder(order, signature);
    }

    function test_RevertWhen_ValidateOrderNotAfterPast() public {
        // Create order with notAfter in the past
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp - 2 hours),
            notAfter: uint48(block.timestamp - 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should revert with OrderExpired
        vm.expectRevert(IMinterV0.OrderExpired.selector);
        minterV0.validateOrder(order, signature);
    }

    function test_RevertWhen_ValidateOrderInvalidTimeWindow() public {
        // Create order with notAfter < notBefore (invalid time window)
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp + 2 hours),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should revert with OrderInvalidTimeWindow
        vm.expectRevert(IMinterV0.OrderInvalidTimeWindow.selector);
        minterV0.validateOrder(order, signature);
    }

    function test_RevertWhen_ValidateOrderInvalidSignature() public {
        // Create order signed by wrong key
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        // Sign with wrong private key (bob's key instead of alice's)
        bytes memory signature = _signOrder(order, bobPrivateKey);

        // Should revert with InvalidSignature
        vm.expectRevert(IMinterV0.InvalidSignature.selector);
        minterV0.validateOrder(order, signature);
    }

    function test_RevertWhen_ValidateOrderInvalidNonce() public {
        // Create order with wrong nonce (should be 0, but using 5)
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 5, // Wrong nonce
            amount: 1_000e18
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should revert with InvalidNonce
        vm.expectRevert(abi.encodeWithSelector(IMinterV0.InvalidNonce.selector, uint48(0), uint48(5)));
        minterV0.validateOrder(order, signature);
    }

    function test_RevertWhen_ValidateOrderAmountTooLarge() public {
        // Create order with amount exceeding max mint amount
        uint208 tooLargeAmount = MAX_MINT_AMOUNT + 1;
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: tooLargeAmount
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should revert with MintAmountTooLarge
        vm.expectRevert(abi.encodeWithSelector(IMinterV0.MintAmountTooLarge.selector, tooLargeAmount, MAX_MINT_AMOUNT));
        minterV0.validateOrder(order, signature);
    }
}
