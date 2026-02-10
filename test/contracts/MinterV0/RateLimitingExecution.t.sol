// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Vm} from "forge-std/src/Vm.sol";
import {VmExt} from "../../utils/VmExt.sol";
import {MinterTest} from "./BaseTest.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";

/**
 * @title MinterV0 Rate Limiting at Execution Time Tests
 * @notice Tests for rate limit enforcement at execution time (not just request time)
 * @dev These tests validate that the rate limit is checked when mints are executed,
 *      preventing users from queueing many requests over time and then executing them
 *      all at once to bypass the rate limit.
 */
contract MinterV0_RateLimitingExecutionTest is MinterTest {
    using VmExt for Vm;

    function setUp() public override {
        super.setUp();

        // Increase max mint amount to 2x rate limit to allow testing rate limit independently
        vm.prank(admin);
        minterV0.setMaxMintAmount(uint208(RATE_LIMIT_AMOUNT * 2));
    }

    /**
     * @notice Helper to create an order with extended validity period
     * @dev Used for tests that advance time significantly
     */
    function _createLongValidityOrder(address beneficiary, uint48 nonce, uint208 amount)
        internal
        view
        returns (IMinterV0.Order memory)
    {
        uint256 currentTimestamp = vm.clone(block.timestamp);

        return IMinterV0.Order({
            beneficiary: beneficiary,
            notBefore: uint48(currentTimestamp),
            notAfter: uint48(currentTimestamp + 7 days), // Extra long validity
            nonce: nonce,
            amount: amount
        });
    }

    /**
     * @notice Test 1: Rate limit enforced at execution time
     * @dev Queue multiple requestMint() calls over several rate-limit periods
     *      (each individually within the limit). Execute them all in a single block.
     *      Assert that execution reverts when the cumulative executed amount in the
     *      current period exceeds the rate limit.
     */
    function test_RevertWhen_ExecutingQueuedRequestsExceedsRateLimit() public {
        // Queue 3 requests, each 40k (total 120k)
        // Each is within rate limit when requested
        // Use long validity orders since we'll advance time significantly
        IMinterV0.Order memory order1 = _createLongValidityOrder(alice, 0, 40_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId1 = minterV0.requestMint(order1, sig1);

        // Advance time by 1 day to reset rate limit window
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD);

        IMinterV0.Order memory order2 = _createLongValidityOrder(bob, 0, 40_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        bytes32 opId2 = minterV0.requestMint(order2, sig2);

        // Advance time by 1 day again
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD);

        IMinterV0.Order memory order3 = _createLongValidityOrder(alice, 1, 40_000e18);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId3 = minterV0.requestMint(order3, sig3);

        // Now advance past the AccessManager delay
        vm.warp(block.timestamp + MINT_DELAY);

        // Execute first two in the same block - should succeed (80k total)
        vm.startPrank(minter);
        minterV0.executeMint(opId1);
        minterV0.executeMint(opId2);

        // Third execution should fail (would be 120k total, exceeds 100k limit)
        vm.expectRevert(
            abi.encodeWithSelector(IMinterV0.RateLimitExceeded.selector, 40_000e18, 20_000e18) // 40k requested, 20k available
        );
        minterV0.executeMint(opId3);
        vm.stopPrank();
    }

    /**
     * @notice Test 2: Sequential execution within limit succeeds
     * @dev Execute mints one at a time, each within the rate limit for the current period.
     *      Assert all succeed.
     */
    function test_SequentialExecutionWithinLimit() public {
        // Queue 3 requests of 30k each (total 90k, within 100k limit)
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 30_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId1 = minterV0.requestMint(order1, sig1);

        IMinterV0.Order memory order2 = _createOrder(bob, 0, 30_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        bytes32 opId2 = minterV0.requestMint(order2, sig2);

        IMinterV0.Order memory order3 = _createOrder(alice, 1, 30_000e18);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId3 = minterV0.requestMint(order3, sig3);

        // Advance past delay
        vm.warp(block.timestamp + MINT_DELAY);

        // Execute all three in sequence - all should succeed (90k total)
        vm.startPrank(minter);
        minterV0.executeMint(opId1);
        assertEq(minterV0.rateLimitMinted(), 30_000e18, "After first execution");

        minterV0.executeMint(opId2);
        assertEq(minterV0.rateLimitMinted(), 60_000e18, "After second execution");

        minterV0.executeMint(opId3);
        assertEq(minterV0.rateLimitMinted(), 90_000e18, "After third execution");
        vm.stopPrank();
    }

    /**
     * @notice Test 3: Rate limit window rolls correctly at execution
     * @dev Execute a mint near the end of a rate-limit period. Advance time past the
     *      period boundary. Execute another mint. Assert the second mint is evaluated
     *      against a fresh window (not the old one).
     */
    function test_RateLimitWindowRollsAtExecution() public {
        // Request and execute first mint of 90k
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 90_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId1 = minterV0.requestMint(order1, sig1);

        vm.warp(block.timestamp + MINT_DELAY);
        vm.prank(minter);
        minterV0.executeMint(opId1);

        assertEq(minterV0.rateLimitMinted(), 90_000e18, "After first execution");
        assertEq(minterV0.rateLimitAvailable(), 10_000e18, "Available after first");

        // Advance time past the rate limit period FIRST (add 1 to ensure we're past the cutoff)
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD + 1);

        // Now the first mint should have expired, giving us a fresh window
        assertEq(minterV0.rateLimitMinted(), 0, "After period expiry");
        assertEq(minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT, "Full capacity available");

        // Request second mint of 90k after the period rolled (so order has fresh notBefore)
        IMinterV0.Order memory order2 = _createOrder(bob, 0, 90_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        bytes32 opId2 = minterV0.requestMint(order2, sig2);

        // Advance time to allow the second order to be executed
        vm.warp(block.timestamp + MINT_DELAY);

        // Execute second mint - should succeed because we're in a fresh period
        vm.prank(minter);
        minterV0.executeMint(opId2);

        assertEq(minterV0.rateLimitMinted(), 90_000e18, "After second execution in new period");
    }

    /**
     * @notice Test 4: rateLimitMinted() reflects executed amounts
     * @dev After executing a mint, call rateLimitMinted() and assert it includes
     *      the executed amount (not just the requested amount from the earlier request time).
     */
    function test_RateLimitMintedReflectsExecutedAmounts() public {
        // Before any execution, minted should be 0
        assertEq(minterV0.rateLimitMinted(), 0, "Initially zero");

        // Request a mint
        IMinterV0.Order memory order = _createOrder(alice, 0, 50_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId = minterV0.requestMint(order, signature);

        // After request but before execution, minted should still be 0 (not recording at request time)
        assertEq(minterV0.rateLimitMinted(), 0, "After request, before execution");

        // Execute the mint
        vm.warp(block.timestamp + MINT_DELAY);
        vm.prank(minter);
        minterV0.executeMint(opId);

        // After execution, minted should reflect the executed amount
        assertEq(minterV0.rateLimitMinted(), 50_000e18, "After execution");
        assertEq(minterV0.rateLimitAvailable(), 50_000e18, "Available after execution");
    }

    /**
     * @notice Test 5: Queued requests that would exceed limit at execution are rejected
     * @dev Request two mints that individually fit the limit. Execute the first (succeeds).
     *      Execute the second in the same period (reverts because cumulative execution
     *      exceeds the limit).
     */
    function test_RevertWhen_SecondQueuedRequestExceedsLimitAtExecution() public {
        // Request two mints of 60k each (individually OK, but together exceed 100k)
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 60_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId1 = minterV0.requestMint(order1, sig1);

        IMinterV0.Order memory order2 = _createOrder(bob, 0, 60_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        bytes32 opId2 = minterV0.requestMint(order2, sig2);

        // Both requests should succeed (no rate limit check at request time)
        assertTrue(opId1 != bytes32(0), "First request succeeded");
        assertTrue(opId2 != bytes32(0), "Second request succeeded");

        // Advance past delay
        vm.warp(block.timestamp + MINT_DELAY);

        // Execute first mint - should succeed
        vm.prank(minter);
        minterV0.executeMint(opId1);
        assertEq(minterV0.rateLimitMinted(), 60_000e18, "After first execution");

        // Execute second mint - should fail (would be 120k total)
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(IMinterV0.RateLimitExceeded.selector, 60_000e18, 40_000e18) // 60k requested, 40k available
        );
        minterV0.executeMint(opId2);
    }

    /**
     * @notice Test that nonce is incremented even without rate limit check
     * @dev This ensures that requestMint always increments nonce on success
     */
    function test_NonceIncrementedOnSuccessfulRequest() public {
        // Request should succeed
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 100_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);

        uint48 nonceBefore = minterV0.nonce(alice);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Nonce should be incremented after successful request
        assertEq(minterV0.nonce(alice), nonceBefore + 1, "Nonce incremented after request");

        // Second request with the same nonce should fail (nonce already used)
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IMinterV0.InvalidNonce.selector, 1, 0)); // expected=1, provided=0
        minterV0.requestMint(order1, sig1);
    }

    /**
     * @notice Test multiple executions across period boundaries
     * @dev Validate that the rolling window works correctly with multiple periods
     */
    function test_MultipleExecutionsAcrossPeriods() public {
        // Period 1: Request and execute 80k
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 80_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId1 = minterV0.requestMint(order1, sig1);

        vm.warp(block.timestamp + MINT_DELAY);
        vm.prank(minter);
        minterV0.executeMint(opId1);
        assertEq(minterV0.rateLimitMinted(), 80_000e18, "Period 1: 80k minted");

        // Request another 80k in same period (but don't execute yet)
        // Use long validity for time advances
        IMinterV0.Order memory order2 = _createLongValidityOrder(bob, 0, 80_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        bytes32 opId2 = minterV0.requestMint(order2, sig2);

        // Advance to period 2 (first mint expires) but keep order2 valid
        // Add 1 to ensure we're past the cutoff, plus MINT_DELAY for order2
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD + 1 + MINT_DELAY);

        // Execute the queued 80k - should succeed in new period (first mint expired)
        // The history cleanup in executeMint will remove the first mint
        vm.prank(minter);
        minterV0.executeMint(opId2);
        assertEq(minterV0.rateLimitMinted(), 80_000e18, "Period 2: 80k minted");

        // Request and execute another 20k in period 2 (total 100k, at limit)
        IMinterV0.Order memory order3 = _createOrder(alice, 1, 20_000e18);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId3 = minterV0.requestMint(order3, sig3);

        vm.warp(block.timestamp + MINT_DELAY);
        vm.prank(minter);
        minterV0.executeMint(opId3);
        assertEq(minterV0.rateLimitMinted(), 100_000e18, "Period 2: 100k minted (at limit)");
    }
}
