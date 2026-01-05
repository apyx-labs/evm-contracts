// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/src/Vm.sol";
import {VmExt} from "../utils/VmExt.sol";
import {MinterTest} from "./BaseTest.sol";
import {MinterV0} from "../../src/MinterV0.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";

/**
 * @title MinterV0 Rate Limiting Tests
 * @notice Comprehensive tests for MinterV0 rate limiting functionality including:
 *   - Capacity tracking (minted and available)
 *   - Rate limit enforcement
 *   - Period expiry and rolling windows
 *   - History management and cleanup
 *   - Multiple beneficiary scenarios
 */
contract MinterV0_RateLimitingTest is MinterTest {
    using VmExt for Vm;

    function setUp() public override {
        super.setUp();

        // Increase max mint amount to 2x rate limit to allow testing rate limit independently
        // Rate limit is 100k, so set max mint to 200k
        vm.prank(admin);
        minterV0.setMaxMintAmount(uint208(RATE_LIMIT_AMOUNT * 2));
    }

    // ----------------------------------------
    // A. Capacity Tracking Tests
    // ----------------------------------------

    function test_RateLimitMinted_InitiallyZero() public view {
        // At deployment, no mints have occurred
        assertEq(minterV0.rateLimitMinted(), 0);
    }

    function test_RateLimitAvailable_InitiallyFull() public view {
        // At deployment, full capacity is available
        assertEq(minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);
    }

    function test_RateLimitInvariant() public {
        // Request various mints and verify invariant holds

        // First mint: 20k
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 20_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Check invariant
        assertEq(minterV0.rateLimitMinted() + minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);

        // Second mint: 30k
        IMinterV0.Order memory order2 = _createOrder(bob, 0, 30_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        // Check invariant again
        assertEq(minterV0.rateLimitMinted() + minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);

        // Third mint: 40k
        IMinterV0.Order memory order3 = _createOrder(alice, 1, 40_000e18);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order3, sig3);

        // Check invariant one more time
        assertEq(minterV0.rateLimitMinted() + minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);
    }

    function test_RateLimitMinted_AfterSingleMint() public {
        uint208 amount = 10_000e18;

        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        minterV0.requestMint(order, signature);

        assertEq(minterV0.rateLimitMinted(), amount);
    }

    function test_RateLimitAvailable_AfterSingleMint() public {
        uint208 amount = 10_000e18;

        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        minterV0.requestMint(order, signature);

        assertEq(minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT - amount);
    }

    function test_RateLimitMinted_AfterMultipleMints() public {
        // Request 3 mints: 20k, 30k, 40k
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 20_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        IMinterV0.Order memory order2 = _createOrder(bob, 0, 30_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        IMinterV0.Order memory order3 = _createOrder(alice, 1, 40_000e18);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order3, sig3);

        // Total minted should be 90k
        assertEq(minterV0.rateLimitMinted(), 90_000e18);
    }

    // ----------------------------------------
    // B. Rate Limit Enforcement Tests
    // ----------------------------------------

    function test_RequestMint_WithinLimit() public {
        uint208 amount = 50_000e18; // Well under 100k limit

        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Should succeed
        assertTrue(operationId != bytes32(0));
    }

    function test_RequestMint_AtExactLimit() public {
        // Request mints totaling exactly 100k
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 60_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        IMinterV0.Order memory order2 = _createOrder(bob, 0, 40_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order2, sig2);

        // Second mint should succeed (exactly at limit)
        assertTrue(operationId != bytes32(0));
        assertEq(minterV0.rateLimitMinted(), RATE_LIMIT_AMOUNT);
        assertEq(minterV0.rateLimitAvailable(), 0);
    }

    function test_RevertWhen_RequestMintExceedsLimit() public {
        // Request 95k first
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 95_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Try to request 10k more (would exceed 100k limit)
        IMinterV0.Order memory order2 = _createOrder(bob, 0, 10_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);

        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IMinterV0.RateLimitExceeded.selector,
                10_000e18, // requested
                5_000e18 // available
            )
        );
        minterV0.requestMint(order2, sig2);
    }

    function test_RevertWhen_FirstMintExceedsLimit() public {
        // Try to request 150k in first mint (exceeds 100k limit)
        uint208 tooLargeAmount = 150_000e18;

        IMinterV0.Order memory order = _createOrder(alice, 0, tooLargeAmount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IMinterV0.RateLimitExceeded.selector, tooLargeAmount, RATE_LIMIT_AMOUNT));
        minterV0.requestMint(order, signature);
    }

    // ----------------------------------------
    // C. Period Expiry Tests
    // ----------------------------------------

    function test_RateLimitMinted_AfterFullPeriodExpiry() public {
        // Request 100k at T=0
        IMinterV0.Order memory order = _createOrder(alice, 0, 100_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order, signature);

        assertEq(minterV0.rateLimitMinted(), 100_000e18);

        // Warp to T=25 hours (past the 24-hour period)
        vm.warp(block.timestamp + 25 hours);

        // All mints should have expired
        assertEq(minterV0.rateLimitMinted(), 0);
    }

    function test_RateLimitAvailable_AfterFullPeriodExpiry() public {
        // Request 100k at T=0
        IMinterV0.Order memory order = _createOrder(alice, 0, 100_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order, signature);

        assertEq(minterV0.rateLimitAvailable(), 0);

        // Warp to T=25 hours
        vm.warp(block.timestamp + 25 hours);

        // Full capacity should be available again
        assertEq(minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);
    }

    function test_RateLimitMinted_PartialExpiry() public {
        // Request 40k at T=0
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 40_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Request 30k at T=12 hours
        vm.warp(block.timestamp + 12 hours);
        IMinterV0.Order memory order2 = _createOrder(bob, 0, 30_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        // Total minted should be 70k
        assertEq(minterV0.rateLimitMinted(), 70_000e18);

        // Warp to T=25 hours (first mint expired, second still valid)
        vm.warp(block.timestamp + 13 hours);

        // Only the 30k from second mint should remain
        assertEq(minterV0.rateLimitMinted(), 30_000e18);
    }

    function test_PeriodBoundary_ExactExpiry() public {
        uint256 startTime = block.timestamp;

        // Request 100k at T=0
        IMinterV0.Order memory order = _createOrder(alice, 0, 100_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order, signature);

        // Warp to exactly T=24 hours
        vm.warp(startTime + 24 hours);

        // Mint should still count (not expired yet - needs to be > 24 hours)
        assertEq(minterV0.rateLimitMinted(), 100_000e18);

        // Warp to T=24 hours + 1 second
        vm.warp(startTime + 24 hours + 1);

        // Now mint should be expired
        assertEq(minterV0.rateLimitMinted(), 0);
    }

    function test_RollingWindow() public {
        // Request 50k at T=0
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 50_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Request 50k at T=12 hours (at limit)
        vm.warp(block.timestamp + 12 hours);
        IMinterV0.Order memory order2 = _createOrder(bob, 0, 50_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        // At limit now
        assertEq(minterV0.rateLimitAvailable(), 0);

        // Warp to T=24h + 1s (first expires)
        vm.warp(block.timestamp + 12 hours + 1);

        // 50k should be available again
        assertEq(minterV0.rateLimitAvailable(), 50_000e18);

        // Request 50k (should succeed)
        IMinterV0.Order memory order3 = _createOrder(alice, 1, 50_000e18);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order3, sig3);

        assertTrue(operationId != bytes32(0));
    }

    // ----------------------------------------
    // D. History Management Tests
    // ----------------------------------------

    function test_MintHistory_QueueGrowth() public {
        // Request 10 mints of 9k each
        uint208 amount = uint208(9_000e18);

        uint256 total = 0;
        for (uint48 i = 0; i < 10; i++) {
            IMinterV0.Order memory order = _createOrder(alice, i, amount);
            bytes memory signature = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, signature);
            total += amount;
        }

        // All should be tracked
        assertEq(minterV0.rateLimitMinted(), total);
    }

    function test_MintHistory_QueueCleanup() public {
        // Request 5 mints at T=0
        uint208 amount = uint208(10_000e18);

        for (uint48 i = 0; i < 5; i++) {
            IMinterV0.Order memory order = _createOrder(alice, i, amount);
            bytes memory signature = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, signature);
        }

        assertEq(minterV0.rateLimitMinted(), 50_000e18);

        // Warp to T=25 hours (all expired)
        vm.warp(block.timestamp + 25 hours);

        // Request new mint (triggers cleanup)
        IMinterV0.Order memory newOrder = _createOrder(bob, 0, 5_000e18);
        bytes memory newSignature = _signOrder(newOrder, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(newOrder, newSignature);

        // Only new mint should count
        assertEq(minterV0.rateLimitMinted(), 5_000e18);
    }

    function test_MintHistory_PreservesRecent() public {
        uint256 startTime = vm.clone(block.timestamp);

        // Request at T=0
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 20_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Request at T=12h
        vm.warp(startTime + 12 hours);
        IMinterV0.Order memory order2 = _createOrder(bob, 0, 30_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        // Request at T=23h
        vm.warp(startTime + 23 hours);
        IMinterV0.Order memory order3 = _createOrder(alice, 1, 25_000e18);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order3, sig3);

        // All three should count
        assertEq(minterV0.rateLimitMinted(), 75_000e18);

        // Warp to T=25h (first mint expired)
        vm.warp(startTime + 25 hours);

        // Only T=12h (30k) and T=23h (25k) should remain
        assertEq(minterV0.rateLimitMinted(), 55_000e18);
    }

    // ----------------------------------------
    // E. Multiple Beneficiary Tests
    // ----------------------------------------

    function test_RateLimit_SharedAcrossBeneficiaries() public {
        // Beneficiary A: 60k
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 60_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Beneficiary B: 30k
        IMinterV0.Order memory order2 = _createOrder(bob, 0, 30_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        // Combined should be 90k
        assertEq(minterV0.rateLimitMinted(), 90_000e18);

        // Beneficiary C tries 20k (would exceed limit)
        uint256 charlieKey = 0x999;
        address charlie = vm.addr(charlieKey);
        IMinterV0.Order memory order3 = IMinterV0.Order({
            beneficiary: charlie,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 24 hours),
            nonce: 0,
            amount: 20_000e18
        });
        bytes memory sig3 = _signOrder(order3, charlieKey);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IMinterV0.RateLimitExceeded.selector, 20_000e18, 10_000e18));
        minterV0.requestMint(order3, sig3);
    }

    function test_RateLimit_IndependentNonces() public {
        // Two beneficiaries can both start at nonce 0
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 40_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        IMinterV0.Order memory order2 = _createOrder(bob, 0, 40_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        // Verify separate nonces
        assertEq(minterV0.nonces(alice), 1);
        assertEq(minterV0.nonces(bob), 1);

        // But shared rate limit pool
        assertEq(minterV0.rateLimitMinted(), 80_000e18);
        assertEq(minterV0.rateLimitAvailable(), 20_000e18);
    }

    // ----------------------------------------
    // F. Edge Cases
    // ----------------------------------------

    function test_RateLimit_MultipleSmallMints() public {
        // Request 10 mints of varying amounts (total = ~100k)
        uint208[10] memory amounts = [
            uint208(10_000e18),
            uint208(10_100e18),
            uint208(10_200e18),
            uint208(10_300e18),
            uint208(10_400e18),
            uint208(9_500e18),
            uint208(9_600e18),
            uint208(9_700e18),
            uint208(9_800e18),
            uint208(10_400e18)
        ];

        for (uint48 i = 0; i < 10; i++) {
            IMinterV0.Order memory order = _createOrder(alice, i, amounts[i]);
            bytes memory signature = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, signature);
        }

        // All should succeed (total = 100k)
        assertEq(minterV0.rateLimitMinted(), 100_000e18);

        // Try 11th (should fail)
        IMinterV0.Order memory failOrder = _createOrder(alice, 10, 10_000e18);
        bytes memory failSignature = _signOrder(failOrder, alicePrivateKey);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IMinterV0.RateLimitExceeded.selector, 10_000e18, 0));
        minterV0.requestMint(failOrder, failSignature);
    }

    function test_RateLimit_VaryingSizes() public {
        // Request: 1k, 5k, 10k, 20k, 64k = 100k
        uint208[5] memory amounts =
            [uint208(1_000e18), uint208(5_000e18), uint208(10_000e18), uint208(20_000e18), uint208(64_000e18)];

        for (uint48 i = 0; i < 5; i++) {
            IMinterV0.Order memory order = _createOrder(alice, i, amounts[i]);
            bytes memory signature = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, signature);
        }

        // All should succeed
        assertEq(minterV0.rateLimitMinted(), 100_000e18);
        assertEq(minterV0.rateLimitAvailable(), 0);
    }

    // ----------------------------------------
    // G. View Function Tests
    // ----------------------------------------

    function test_ViewFunctions_Consistency() public {
        // Request a mint
        IMinterV0.Order memory order = _createOrder(alice, 0, 50_000e18);
        bytes memory signature = _signOrder(order, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order, signature);

        // Call rateLimitMinted() multiple times
        uint256 minted1 = minterV0.rateLimitMinted();
        uint256 minted2 = minterV0.rateLimitMinted();
        uint256 minted3 = minterV0.rateLimitMinted();

        // All should be consistent
        assertEq(minted1, minted2);
        assertEq(minted2, minted3);
        assertEq(minted1, 50_000e18);
    }

    function test_ViewFunctions_Relationship() public {
        // Request various mints at different times
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 30_000e18);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        // Check relationship
        assertEq(minterV0.rateLimitMinted() + minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);

        vm.warp(block.timestamp + 12 hours);

        IMinterV0.Order memory order2 = _createOrder(bob, 0, 40_000e18);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);
        vm.prank(minter);
        minterV0.requestMint(order2, sig2);

        // Check relationship again
        assertEq(minterV0.rateLimitMinted() + minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);

        vm.warp(block.timestamp + 13 hours);

        // After first expires
        assertEq(minterV0.rateLimitMinted() + minterV0.rateLimitAvailable(), RATE_LIMIT_AMOUNT);
    }

    function test_ViewFunctions_RateLimit() public {
        // Check initial values
        (uint256 amount, uint48 period) = minterV0.rateLimit();
        assertEq(amount, RATE_LIMIT_AMOUNT);
        assertEq(period, RATE_LIMIT_PERIOD);

        // Update rate limit
        uint256 newAmount = 200_000e18;
        uint48 newPeriod = uint48(2 days);

        vm.prank(admin);
        minterV0.setRateLimit(newAmount, newPeriod);

        // Verify new values returned
        (uint256 updatedAmount, uint48 updatedPeriod) = minterV0.rateLimit();
        assertEq(updatedAmount, newAmount);
        assertEq(updatedPeriod, newPeriod);
    }

    // ----------------------------------------
    // Phase 5b: Large Queue Gas Testing
    // ----------------------------------------

    function test_RateLimit_LargeQueueGasUsage() public {
        // Fill queue with a large number of mints
        for (uint256 i = 0; i < LARGE_NUM_MINTS; i++) {
            IMinterV0.Order memory order = _createOrder(alice, uint48(i), 100e18);
            bytes memory sig = _signOrder(order, alicePrivateKey);

            vm.prank(minter);
            uint256 gasBefore = gasleft();
            minterV0.requestMint(order, sig);
            uint256 gasUsed = gasBefore - gasleft();

            // Verify gas usage stays reasonable (under 500k for requestMint)
            assertLt(gasUsed, REASONABLE_GAS_LIMIT, "requestMint gas usage too high");
        }

        // Verify queue has 150 records
        assertEq(minterV0.rateLimitMinted(), LARGE_NUM_MINTS * 100e18);
    }

    function test_RateLimit_LargeQueueCleanup() public {
        // Fill queue with a large number of mints
        // Use 100e18 per mint to avoid rate limit issues
        uint208 mintAmount = 100e18;
        for (uint256 i = 0; i < LARGE_NUM_MINTS; i++) {
            IMinterV0.Order memory order = _createOrder(alice, uint48(i), mintAmount);
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        // Advance time to expire all records
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD + 1);

        // Measure gas for automatic cleanup via requestMint
        IMinterV0.Order memory cleanupOrder = _createOrder(alice, uint48(LARGE_NUM_MINTS), 1000e18);
        bytes memory cleanupSig = _signOrder(cleanupOrder, alicePrivateKey);

        vm.prank(minter);
        uint256 gasBefore = gasleft();
        minterV0.requestMint(cleanupOrder, cleanupSig);
        uint256 gasUsed = gasBefore - gasleft();

        // Should clean all LARGE_NUM_MINTS expired records + process new mint
        // Verify stays under Fusaka limit (2^24 = 16,777,216 gas)
        assertLt(gasUsed, REASONABLE_GAS_LIMIT, "Cleanup gas exceeds Fusaka limit");
    }

    function test_CleanMintHistory_Manual() public {
        // Fill queue with a large number of mints
        // Use 100e18 per mint to avoid rate limit issues
        uint208 mintAmount = 100e18;
        for (uint256 i = 0; i < LARGE_NUM_MINTS; i++) {
            IMinterV0.Order memory order = _createOrder(alice, uint48(i), mintAmount);
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        // Advance time to expire all
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD + 1);

        // Manually clean 50 records at a time
        for (uint256 i = 0; i < LARGE_NUM_MINTS / 50; i++) {
            vm.prank(minter);
            uint256 gasBefore = gasleft();
            uint32 cleaned = minterV0.cleanMintHistory(50);
            uint256 gasUsed = gasBefore - gasleft();

            assertEq(cleaned, 50, "Should clean 50 records");
            assertLt(gasUsed, REASONABLE_GAS_LIMIT, "Manual cleanup gas too high for 50 records");
        }

        // Verify queue empty
        assertEq(minterV0.rateLimitMinted(), 0);
    }

    function test_CleanMintHistory_PartialExpiry() public {
        // Add 50 old mints
        for (uint256 i = 0; i < 50; i++) {
            IMinterV0.Order memory order = _createOrder(alice, uint48(i), 800e18);
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        // Advance time by half period
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD / 2);

        // Add 50 new mints
        for (uint256 i = 50; i < 100; i++) {
            IMinterV0.Order memory order = _createOrder(alice, uint48(i), 800e18);
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        // Advance time to expire first 50
        vm.warp(block.timestamp + RATE_LIMIT_PERIOD / 2 + 1);

        // Clean should only remove expired records
        vm.prank(minter);
        uint32 cleaned = minterV0.cleanMintHistory(100);

        assertEq(cleaned, 50, "Should only clean 50 expired records");
        assertEq(minterV0.rateLimitMinted(), 50 * 800e18, "Should have 50 records remaining");
    }

    function test_CleanMintHistory_AccessControl() public {
        // Add some mints
        for (uint256 i = 0; i < 10; i++) {
            IMinterV0.Order memory order = _createOrder(alice, uint48(i), 800e18);
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        vm.warp(block.timestamp + RATE_LIMIT_PERIOD + 1);

        // Should revert for unauthorized user
        vm.prank(bob);
        vm.expectRevert();
        minterV0.cleanMintHistory(10);
    }

    function test_CleanMintHistory_EmptyQueue() public {
        // Clean empty queue should return 0
        vm.prank(minter);
        uint32 cleaned = minterV0.cleanMintHistory(10);
        assertEq(cleaned, 0);
    }

    function test_CleanMintHistory_NoExpiredRecords() public {
        // Add recent mints
        for (uint256 i = 0; i < 10; i++) {
            IMinterV0.Order memory order = _createOrder(alice, uint48(i), 800e18);
            bytes memory sig = _signOrder(order, alicePrivateKey);
            vm.prank(minter);
            minterV0.requestMint(order, sig);
        }

        // Try to clean without advancing time
        vm.prank(minter);
        uint32 cleaned = minterV0.cleanMintHistory(10);

        assertEq(cleaned, 0, "Should not clean non-expired records");
        assertEq(minterV0.rateLimitMinted(), 10 * 800e18, "All records should remain");
    }
}
