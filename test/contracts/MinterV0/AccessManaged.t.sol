// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {MinterTest} from "./BaseTest.sol";
import {MinterV0} from "../../../src/MinterV0.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";

/**
 * @title MinterV0 AccessManager Integration Tests
 * @notice Tests for AccessManager-specific behavior and edge cases
 * @dev Verifies that AccessManager constraints don't cause unexpected failures
 */
contract MinterV0_AccessManagedTest is MinterTest {
    function setUp() public override {
        super.setUp();

        // Increase max mint amount to 2x rate limit to allow testing without rate limit interference
        vm.prank(admin);
        minterV0.setMaxMintAmount(uint208(RATE_LIMIT_AMOUNT * 2));
    }

    /**
     * @notice Tests that expired orders DO block new mints when hitting the 256 operation ID limit
     * @dev Background: AccessManager tracks operations by operation ID (hash of data).
     *      We append nonce % 256 to the data, so a user can have at most 256 concurrent orders.
     *      When orders expire but aren't cleared from AccessManager, new mints ARE blocked.
     *
     * This test DOCUMENTS the 256 operation ID limit issue:
     * - Create 256 orders with operation IDs 0-255 (from nonce % 256)
     * - Wait for orders to expire
     * - Try to create a new order with nonce 256 (256 % 256 = 0)
     * - AccessManager rejects with AccessManagerAlreadyScheduled
     * - This proves expired orders block new mints unless executed or cancelled
     */
    function test_ExpiredOrdersBlockNewMintsIfNotCleared() public {
        // Use 100e18 per mint to avoid rate limit issues (256 * 100e18 = 25,600e18 < 100k limit)
        uint208 mintAmount = 100e18;
        uint256 numOrders = 256;

        // Create 256 orders with short expiry (MINT_DELAY + 1)
        for (uint256 i = 0; i < numOrders; i++) {
            IMinterV0.Order memory tempOrder = IMinterV0.Order({
                beneficiary: alice,
                notBefore: uint48(block.timestamp),
                notAfter: uint48(block.timestamp + MINT_DELAY + 1),
                nonce: uint48(i),
                amount: mintAmount
            });
            bytes memory tempSig = _signOrder(tempOrder, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(tempOrder, tempSig);
        }

        // All 256 orders are now scheduled in AccessManager
        assertEq(minterV0.rateLimitMinted(), numOrders * mintAmount);

        // Warp past the notAfter time (MINT_DELAY + 2)
        // Orders are now expired but still in AccessManager
        vm.warp(block.timestamp + MINT_DELAY + 2);

        // Now try to create a new order with nonce 256
        // This will wrap around (256 % 256 = 0), creating the SAME operation ID as nonce 0
        // AccessManager will reject this with AccessManagerAlreadyScheduled
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 24 hours),
            nonce: uint48(numOrders), // nonce 256 wraps to 0
            amount: mintAmount
        });
        bytes memory sig = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        vm.expectRevert(); // AccessManagerAlreadyScheduled error
        minterV0.requestMint(order, sig);

        // Verify no new order was created (rate limit unchanged)
        assertEq(minterV0.rateLimitMinted(), numOrders * mintAmount);
    }

    /**
     * @notice Tests that executing orders frees operation IDs, allowing continued minting
     * @dev Demonstrates that the 256 order limit can be managed by executing orders
     */
    function test_ContinuedMinting_AfterExecutingOrders() public {
        uint208 mintAmount = 100e18;
        uint256 numOrders = 256;

        // Create and execute 256 orders
        // Use long expiry to avoid expiration during the test
        uint256 startTime = block.timestamp;
        for (uint256 i = 0; i < numOrders; i++) {
            IMinterV0.Order memory order = IMinterV0.Order({
                beneficiary: alice,
                notBefore: uint48(startTime),
                notAfter: uint48(startTime + 365 days), // Long expiry
                nonce: uint48(i),
                amount: mintAmount
            });
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            bytes32 opId = minterV0.requestMint(order, sig);

            // Execute the order immediately (after delay)
            vm.warp(block.timestamp + MINT_DELAY + 1);
            vm.prank(minter);
            minterV0.executeMint(opId);
        }

        // All orders executed, operation IDs freed
        // Now create 256 MORE orders - should succeed because operation IDs are freed
        for (uint256 i = 0; i < numOrders; i++) {
            IMinterV0.Order memory order = IMinterV0.Order({
                beneficiary: alice,
                notBefore: uint48(block.timestamp),
                notAfter: uint48(block.timestamp + 365 days), // Long expiry
                nonce: uint48(numOrders + i), // nonces 256-511 (wrap to 0-255)
                amount: mintAmount
            });
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        // Success! All 512 orders created (256 executed, 256 pending)
        // However, due to time advancement, old mints may have expired from the rate limit window
        // We only verify that the second batch was successfully created
        assertTrue(minterV0.rateLimitMinted() >= numOrders * mintAmount);
    }

    /**
     * @notice Tests that canceling expired orders frees operation IDs, allowing continued minting
     * @dev Demonstrates that the 256 order limit can be managed by canceling expired orders
     *      This is the primary recovery mechanism when orders expire without execution
     */
    function test_ContinuedMinting_AfterCancelingExpiredOrders() public {
        uint208 mintAmount = 100e18;
        uint256 numOrders = 256;

        // Create 256 orders with short expiry
        bytes32[] memory operationIds = new bytes32[](numOrders);
        for (uint256 i = 0; i < numOrders; i++) {
            IMinterV0.Order memory order = IMinterV0.Order({
                beneficiary: alice,
                notBefore: uint48(block.timestamp),
                notAfter: uint48(block.timestamp + MINT_DELAY + 1),
                nonce: uint48(i),
                amount: mintAmount
            });
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            operationIds[i] = minterV0.requestMint(order, sig);
        }

        // All 256 orders are now pending in AccessManager
        assertEq(minterV0.rateLimitMinted(), numOrders * mintAmount);

        // Warp past expiry
        vm.warp(block.timestamp + MINT_DELAY + 2);

        // Cancel all expired orders
        for (uint256 i = 0; i < numOrders; i++) {
            vm.prank(guardian);
            minterV0.cancelMint(operationIds[i]);
        }

        // All operation IDs now freed
        // Create 256 MORE orders - should succeed because operation IDs are freed
        for (uint256 i = 0; i < numOrders; i++) {
            IMinterV0.Order memory order = IMinterV0.Order({
                beneficiary: alice,
                notBefore: uint48(block.timestamp),
                notAfter: uint48(block.timestamp + 24 hours),
                nonce: uint48(numOrders + i), // nonces 256-511 (wrap to 0-255)
                amount: mintAmount
            });
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        // Success! All new orders created
        // Note: Cancelled orders still count in rate limit (they're in mint history)
        // This is intentional - cancellation doesn't free rate limit capacity (prevents gaming)
        assertEq(minterV0.rateLimitMinted(), numOrders * 2 * mintAmount);
    }
}
