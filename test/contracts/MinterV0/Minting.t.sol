// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {MinterTest} from "./BaseTest.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";

/**
 * @title MinterV0 Mint Tests
 * @notice Comprehensive tests for MinterV0 minting functionality including:
 *   - Order validation (signatures, nonces, time windows)
 *   - Request and execute mint flows
 *   - Access control
 *   - Integration with AccessManager and ApxUSD
 */
contract MinterV0_MintTest is MinterTest {
    function setUp() public override {
        super.setUp();

        // Increase rate limit to max to allow testing non-rate limited behavior
        vm.prank(admin);
        minterV0.setRateLimit(type(uint208).max, RATE_LIMIT_PERIOD);
    }

    function test_FullMintFlow() public {
        uint208 amount = 5_000e18;

        // 1. Create and sign order
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        // 2. Submit mint request
        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // 3. Verify request is pending
        assertEq(apxUSD.balanceOf(alice), 0);
        IMinterV0.Order memory pendingOrder = minterV0.pendingOrder(operationId);
        assertEq(pendingOrder.beneficiary, alice);
        assertEq(pendingOrder.amount, amount);

        // 4. Fast forward past delay
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // 5. Execute mint
        vm.prank(minter);
        minterV0.executeMint(operationId);

        // 6. Verify tokens received
        assertEq(apxUSD.balanceOf(alice), amount);
        assertEq(apxUSD.totalSupply(), amount);
    }

    function test_MultipleBeneficiariesMinting() public {
        uint208 amount1 = 3_000e18;
        uint208 amount2 = 7_000e18;

        // Alice mints
        IMinterV0.Order memory order1 = _createOrder(alice, 0, amount1);
        bytes memory signature1 = _signOrder(order1, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId1 = minterV0.requestMint(order1, signature1);

        // Bob mints
        IMinterV0.Order memory order2 = _createOrder(bob, 0, amount2);
        bytes memory signature2 = _signOrder(order2, bobPrivateKey);

        vm.prank(minter);
        bytes32 operationId2 = minterV0.requestMint(order2, signature2);

        // Fast forward and execute both
        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId1);

        vm.prank(minter);
        minterV0.executeMint(operationId2);

        // Verify balances
        assertEq(apxUSD.balanceOf(alice), amount1);
        assertEq(apxUSD.balanceOf(bob), amount2);
        assertEq(apxUSD.totalSupply(), amount1 + amount2);
    }

    function test_MintAndTransfer() public {
        uint208 amount = 5_000e18;

        // Mint to alice
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId);

        // Transfer to bob
        uint256 transferAmount = 2_000e18;
        vm.prank(alice);
        apxUSD.transfer(bob, transferAmount);

        assertEq(apxUSD.balanceOf(alice), amount - transferAmount);
        assertEq(apxUSD.balanceOf(bob), transferAmount);
    }

    function test_MintUpToSupplyCap() public {
        // Update max mint amount and rate limit to allow larger mints
        vm.prank(admin);
        minterV0.setMaxMintAmount(uint208(APX_SUPPLY_CAP));

        // Mint up to supply cap
        IMinterV0.Order memory order = _createOrder(alice, 0, uint208(APX_SUPPLY_CAP));
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId);

        assertEq(apxUSD.totalSupply(), APX_SUPPLY_CAP);
        assertEq(apxUSD.supplyCapRemaining(), 0);
    }

    function test_RevertWhen_MintExceedsSupplyCapAfterExecution() public {
        // Update max mint amount and rate limit
        vm.prank(admin);
        minterV0.setMaxMintAmount(uint208(APX_SUPPLY_CAP));

        // Create two mint requests that together exceed supply cap
        uint208 amount = uint208(APX_SUPPLY_CAP / 2 + 1);

        IMinterV0.Order memory order1 = _createOrder(alice, 0, amount);
        bytes memory signature1 = _signOrder(order1, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId1 = minterV0.requestMint(order1, signature1);

        IMinterV0.Order memory order2 = _createOrder(bob, 0, amount);
        bytes memory signature2 = _signOrder(order2, bobPrivateKey);

        vm.prank(minter);
        bytes32 operationId2 = minterV0.requestMint(order2, signature2);

        // Fast forward
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // First execution succeeds
        vm.prank(minter);
        minterV0.executeMint(operationId1);
        assertEq(apxUSD.balanceOf(alice), amount);

        // Second execution should fail (exceeds supply cap)
        vm.prank(minter);
        vm.expectRevert();
        minterV0.executeMint(operationId2);
    }

    function test_PauseAndUnpauseTransfers() public {
        uint208 amount = 5_000e18;

        // Mint tokens
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId);

        // Pause transfers
        vm.prank(admin);
        apxUSD.pause();

        // Transfer should fail
        vm.prank(alice);
        vm.expectRevert();
        apxUSD.transfer(bob, 1_000e18);

        // Unpause
        vm.prank(admin);
        apxUSD.unpause();

        // Transfer should succeed
        vm.prank(alice);
        apxUSD.transfer(bob, 1_000e18);

        assertEq(apxUSD.balanceOf(bob), 1_000e18);
    }

    function test_UpdateMaxMintAmount() public {
        uint208 newMaxMintAmount = 20_000e18;

        // Update parameter
        vm.prank(admin);
        minterV0.setMaxMintAmount(newMaxMintAmount);

        assertEq(minterV0.maxMintAmount(), newMaxMintAmount);

        // Mint with new max amount
        uint208 amount = 15_000e18;

        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId);

        assertEq(apxUSD.balanceOf(alice), amount);
    }

    function test_IncreaseSupplyCapAndMintMore() public {
        // Mint close to supply cap
        vm.prank(admin);
        minterV0.setMaxMintAmount(uint208(APX_SUPPLY_CAP));

        uint208 amount = uint208(APX_SUPPLY_CAP - 1_000e18);

        IMinterV0.Order memory order1 = _createOrder(alice, 0, amount);
        bytes memory signature1 = _signOrder(order1, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId1 = minterV0.requestMint(order1, signature1);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId1);

        // Increase supply cap
        vm.prank(admin);
        apxUSD.setSupplyCap(APX_SUPPLY_CAP * 2);

        // Mint more
        IMinterV0.Order memory order2 = _createOrder(alice, 1, uint208(500_000e18));
        bytes memory signature2 = _signOrder(order2, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId2 = minterV0.requestMint(order2, signature2);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId2);

        assertEq(apxUSD.totalSupply(), amount + 500_000e18);
    }

    function test_NonceIncrementsCorrectly() public {
        // First mint
        IMinterV0.Order memory order1 = _createOrder(alice, 0, 1_000e18);
        bytes memory signature1 = _signOrder(order1, alicePrivateKey);

        vm.prank(minter);
        minterV0.requestMint(order1, signature1);

        assertEq(minterV0.nonce(alice), 1);

        // Second mint with incremented nonce
        IMinterV0.Order memory order2 = _createOrder(alice, 1, 2_000e18);
        bytes memory signature2 = _signOrder(order2, alicePrivateKey);

        vm.prank(minter);
        minterV0.requestMint(order2, signature2);

        assertEq(minterV0.nonce(alice), 2);
    }

    function test_RevertWhen_UnauthorizedMinterCallsRequestMint() public {
        uint208 amount = 5_000e18;

        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Try to request mint from unauthorized address
        vm.prank(alice);
        vm.expectRevert();
        minterV0.requestMint(order, signature);
    }

    function test_RevertWhen_UnauthorizedMinterCallsExecuteMint() public {
        uint208 amount = 5_000e18;

        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        // Try to execute from unauthorized address
        vm.prank(alice);
        vm.expectRevert();
        minterV0.executeMint(operationId);
    }

    function test_RevertWhen_ExecuteMintNonExistentOrder() public {
        // Try to execute random operationId that was never requested
        bytes32 fakeOperationId = bytes32(uint256(12345));

        vm.prank(minter);
        vm.expectRevert(IMinterV0.OrderNotFound.selector);
        minterV0.executeMint(fakeOperationId);
    }

    function test_RevertWhen_ExecuteMintTwice() public {
        uint208 amount = 5_000e18;

        // Request and execute once
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        vm.warp(block.timestamp + MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId);

        // Verify first execution succeeded
        assertEq(apxUSD.balanceOf(alice), amount);

        // Try to execute same operationId again
        vm.prank(minter);
        vm.expectRevert(IMinterV0.OrderNotFound.selector);
        minterV0.executeMint(operationId);
    }

    function test_RevertWhen_ExecuteMintAfterNotAfter() public {
        uint208 amount = 3_000e18;

        // Create order with notAfter = current time + 2 hours
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 2 hours),
            nonce: 0,
            amount: amount
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Verify it's executable now (before notAfter)
        assertGt(order.notAfter, block.timestamp);

        // Now warp past notAfter
        vm.warp(order.notAfter + 1 seconds);

        // Should revert with OrderExpired (even though it was scheduled)
        vm.prank(minter);
        vm.expectRevert(IMinterV0.OrderExpired.selector);
        minterV0.executeMint(operationId);

        // Note: Order is NOT cleaned up when execution reverts (transaction rolled back)
        // This is expected behavior - the expired order remains in storage
        IMinterV0.Order memory retrieved = minterV0.pendingOrder(operationId);
        assertEq(retrieved.beneficiary, alice); // Order still exists
    }

    function test_RequestMintWithNotBeforeInPast() public {
        uint208 amount = 2_000e18;

        // Create order with notBefore in the past
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp - 1 hours),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: amount
        });

        bytes memory signature = _signOrder(order, alicePrivateKey);

        // Should succeed (already valid)
        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        assertTrue(operationId != bytes32(0));
    }

    function test_RequestMintMultipleBeneficiaries() public {
        uint208 amount = 3_000e18;

        // Request mint for alice (nonce 0)
        IMinterV0.Order memory order1 = _createOrder(alice, 0, amount);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);

        vm.prank(minter);
        bytes32 opId1 = minterV0.requestMint(order1, sig1);

        // Request mint for bob (also nonce 0 - independent tracking)
        IMinterV0.Order memory order2 = _createOrder(bob, 0, amount);
        bytes memory sig2 = _signOrder(order2, bobPrivateKey);

        vm.prank(minter);
        bytes32 opId2 = minterV0.requestMint(order2, sig2);

        // Verify both nonces independent
        assertEq(minterV0.nonce(alice), 1);
        assertEq(minterV0.nonce(bob), 1);

        // Verify both orders stored
        IMinterV0.Order memory storedOrder1 = minterV0.pendingOrder(opId1);
        assertEq(storedOrder1.beneficiary, alice);

        IMinterV0.Order memory storedOrder2 = minterV0.pendingOrder(opId2);
        assertEq(storedOrder2.beneficiary, bob);
    }

    function test_RevertWhen_RequestMintNonceReuse() public {
        uint208 amount = 2_000e18;

        // First mint with nonce 0
        IMinterV0.Order memory order1 = _createOrder(alice, 0, amount);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);

        vm.prank(minter);
        minterV0.requestMint(order1, sig1);

        assertEq(minterV0.nonce(alice), 1);

        // Try to reuse nonce 0 (should fail)
        IMinterV0.Order memory order2 = _createOrder(alice, 0, amount + 1);
        bytes memory sig2 = _signOrder(order2, alicePrivateKey);

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IMinterV0.InvalidNonce.selector, uint48(1), uint48(0)));
        minterV0.requestMint(order2, sig2);
    }

    // ----------------------------------------
    // Cancel Mint Tests
    // ----------------------------------------

    function test_CancelMint_ByGuardian() public {
        uint208 amount = 3_000e18;

        // Create and request mint
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Verify order is pending
        IMinterV0.Order memory pendingOrder = minterV0.pendingOrder(operationId);
        assertEq(pendingOrder.beneficiary, alice);
        assertEq(pendingOrder.amount, amount);

        // Cancel by guardian
        cancelMint(operationId);

        // Verify order is removed
        IMinterV0.Order memory cancelledOrder = minterV0.pendingOrder(operationId);
        assertEq(cancelledOrder.beneficiary, address(0));
        assertEq(cancelledOrder.amount, 0);

        // Verify alice did not receive tokens
        assertEq(apxUSD.balanceOf(alice), 0);
    }

    function test_CancelMint_EmitsEvent() public {
        uint208 amount = 2_500e18;

        // Create and request mint
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Expect MintCancelled event
        vm.expectEmit(true, true, true, true);
        emit IMinterV0.MintCancelled(operationId, alice, guardian);

        cancelMint(operationId);
    }

    function test_CancelMint_DoesNotFreeRateLimitCapacity() public {
        uint208 amount = 5_000e18;

        // Create and request mint
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Verify rate limit updated
        assertEq(minterV0.rateLimitMinted(), amount);

        // Cancel the mint
        cancelMint(operationId);

        // Rate limit should STILL include cancelled amount (prevents gaming)
        assertEq(minterV0.rateLimitMinted(), amount);
    }

    function test_RevertWhen_CancelMintNonExistentOrder() public {
        // Try to cancel an operation that was never created
        bytes32 fakeOperationId = bytes32(uint256(99999));

        vm.prank(guardian);
        vm.expectRevert(IMinterV0.OrderNotFound.selector);
        minterV0.cancelMint(fakeOperationId);
    }

    function test_RevertWhen_CancelMintTwice() public {
        uint208 amount = 3_000e18;

        // Create and request mint
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Cancel once
        cancelMint(operationId);

        // Try to cancel again (should fail - order no longer exists)
        vm.prank(guardian);
        vm.expectRevert(IMinterV0.OrderNotFound.selector);
        minterV0.cancelMint(operationId);
    }

    function test_RevertWhen_CancelMintAlreadyExecuted() public {
        uint208 amount = 3_000e18;

        // Create and request mint
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Execute the mint
        vm.warp(block.timestamp + MINT_DELAY + 1);
        vm.prank(minter);
        minterV0.executeMint(operationId);

        // Verify execution succeeded
        assertEq(apxUSD.balanceOf(alice), amount);

        // Try to cancel after execution (should fail - order no longer exists)
        vm.prank(guardian);
        vm.expectRevert(IMinterV0.OrderNotFound.selector);
        minterV0.cancelMint(operationId);
    }

    function test_RevertWhen_CancelMintUnauthorized() public {
        uint208 amount = 3_000e18;

        // Create and request mint
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Try to cancel from unauthorized address (alice)
        vm.prank(alice);
        vm.expectRevert();
        minterV0.cancelMint(operationId);

        // Try to cancel from unauthorized address (bob)
        vm.prank(bob);
        vm.expectRevert();
        minterV0.cancelMint(operationId);

        // Verify order still exists
        IMinterV0.Order memory pendingOrder = minterV0.pendingOrder(operationId);
        assertEq(pendingOrder.beneficiary, alice);
    }

    function test_CancelMint_AllowsNewMintWithSameParameters() public {
        uint208 amount = 3_000e18;

        // Create and request mint
        IMinterV0.Order memory order1 = _createOrder(alice, 0, amount);
        bytes memory signature1 = _signOrder(order1, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId1 = minterV0.requestMint(order1, signature1);

        // Cancel the mint
        cancelMint(operationId1);

        // Create a new mint with next nonce (nonce 1)
        IMinterV0.Order memory order2 = _createOrder(alice, 1, amount);
        bytes memory signature2 = _signOrder(order2, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId2 = minterV0.requestMint(order2, signature2);

        // Execute the new mint
        vm.warp(block.timestamp + MINT_DELAY + 1);
        vm.prank(minter);
        minterV0.executeMint(operationId2);

        // Verify tokens received
        assertEq(apxUSD.balanceOf(alice), amount);
    }

    function test_CancelMint_MultiplePendingOrders() public {
        uint208 amount = 2_000e18;

        // Create three pending orders
        IMinterV0.Order memory order1 = _createOrder(alice, 0, amount);
        bytes memory sig1 = _signOrder(order1, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId1 = minterV0.requestMint(order1, sig1);

        IMinterV0.Order memory order2 = _createOrder(alice, 1, amount);
        bytes memory sig2 = _signOrder(order2, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId2 = minterV0.requestMint(order2, sig2);

        IMinterV0.Order memory order3 = _createOrder(alice, 2, amount);
        bytes memory sig3 = _signOrder(order3, alicePrivateKey);
        vm.prank(minter);
        bytes32 opId3 = minterV0.requestMint(order3, sig3);

        // Cancel the middle order
        cancelMint(opId2);

        // Verify order2 is cancelled
        IMinterV0.Order memory cancelled = minterV0.pendingOrder(opId2);
        assertEq(cancelled.beneficiary, address(0));

        // Verify orders 1 and 3 still exist
        IMinterV0.Order memory pending1 = minterV0.pendingOrder(opId1);
        assertEq(pending1.beneficiary, alice);

        IMinterV0.Order memory pending3 = minterV0.pendingOrder(opId3);
        assertEq(pending3.beneficiary, alice);

        // Execute remaining orders
        vm.warp(block.timestamp + MINT_DELAY + 1);
        vm.prank(minter);
        minterV0.executeMint(opId1);
        vm.prank(minter);
        minterV0.executeMint(opId3);

        // Verify only 2 orders executed (4_000e18 total)
        assertEq(apxUSD.balanceOf(alice), amount * 2);
    }

    // ----------------------------------------
    // Mint Status Tests
    // ----------------------------------------

    function test_MintStatus_NotFound() public view {
        // Query status for operation that never existed
        bytes32 fakeOpId = bytes32(uint256(12345));

        IMinterV0.MintStatus status = minterV0.mintStatus(fakeOpId);
        assertEq(uint256(status), uint256(IMinterV0.MintStatus.NotFound));
    }

    function test_MintStatus_ScheduledDuringAccessManagerDelay() public {
        uint208 amount = 3_000e18;

        // Create order with notBefore in the past
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Immediately after request, AccessManager delay hasn't passed yet
        // Status should be Scheduled
        IMinterV0.MintStatus status = minterV0.mintStatus(operationId);
        assertEq(uint256(status), uint256(IMinterV0.MintStatus.Scheduled));
    }

    function test_MintStatus_Ready() public {
        uint208 amount = 3_000e18;

        // Create and request order
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Fast forward past AccessManager delay
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // Status should be Ready (AccessManager delay passed, within time window)
        IMinterV0.MintStatus status = minterV0.mintStatus(operationId);
        assertEq(uint256(status), uint256(IMinterV0.MintStatus.Ready));
    }

    function test_MintStatus_Expired() public {
        uint208 amount = 3_000e18;

        // Create order with short expiry
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + MINT_DELAY + 1 hours),
            nonce: 0,
            amount: amount
        });
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Warp past notAfter
        vm.warp(block.timestamp + MINT_DELAY + 2 hours);

        // Status should be Expired
        IMinterV0.MintStatus status = minterV0.mintStatus(operationId);
        assertEq(uint256(status), uint256(IMinterV0.MintStatus.Expired));
    }

    function test_MintStatus_NotFoundAfterExecution() public {
        uint208 amount = 3_000e18;

        // Create and request order
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Fast forward and execute
        vm.warp(block.timestamp + MINT_DELAY + 1);
        vm.prank(minter);
        minterV0.executeMint(operationId);

        // Status should be NotFound (order was deleted after execution)
        IMinterV0.MintStatus status = minterV0.mintStatus(operationId);
        assertEq(uint256(status), uint256(IMinterV0.MintStatus.NotFound));
    }

    function test_MintStatus_NotFoundAfterCancellation() public {
        uint208 amount = 3_000e18;

        // Create and request order
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Cancel order
        cancelMint(operationId);

        // Status should be NotFound (order was deleted after cancellation)
        IMinterV0.MintStatus status = minterV0.mintStatus(operationId);
        assertEq(uint256(status), uint256(IMinterV0.MintStatus.NotFound));
    }

    function test_MintStatus_TransitionFromScheduledToReady() public {
        uint208 amount = 3_000e18;

        // Create and request order
        IMinterV0.Order memory order = _createOrder(alice, 0, amount);
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Initially Scheduled (AccessManager delay not passed)
        IMinterV0.MintStatus status1 = minterV0.mintStatus(operationId);
        assertEq(uint256(status1), uint256(IMinterV0.MintStatus.Scheduled));

        // Fast forward past AccessManager delay
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // Now Ready
        IMinterV0.MintStatus status2 = minterV0.mintStatus(operationId);
        assertEq(uint256(status2), uint256(IMinterV0.MintStatus.Ready));
    }

    function test_MintStatus_TransitionFromReadyToExpired() public {
        uint208 amount = 3_000e18;

        // Create order with short expiry
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + MINT_DELAY + 30 minutes),
            nonce: 0,
            amount: amount
        });
        bytes memory signature = _signOrder(order, alicePrivateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        // Fast forward past AccessManager delay but before notAfter
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // Should be Ready
        IMinterV0.MintStatus status1 = minterV0.mintStatus(operationId);
        assertEq(uint256(status1), uint256(IMinterV0.MintStatus.Ready));

        // Warp past notAfter
        vm.warp(block.timestamp + 1 hours);

        // Now Expired
        IMinterV0.MintStatus status2 = minterV0.mintStatus(operationId);
        assertEq(uint256(status2), uint256(IMinterV0.MintStatus.Expired));
    }

    /**
     * @notice Comprehensive fuzz test for minting with varied nonce values and multiple beneficiaries
     * @dev This test fuzzes:
     *   - Initial nonce value (starting point for each beneficiary)
     *   - Mint amounts (for each individual mint)
     *   - Number of mints per beneficiary
     *   - Multiple beneficiaries (alice and bob)
     */
    function testFuzz_MintWithVariedNoncesAndMultipleBeneficiaries(
        uint48 initialNonce,
        uint208 mintAmount,
        uint8 numMints
    ) public {
        // Bound inputs to reasonable ranges
        // Keep initialNonce small (0-50) to make the test practical while still covering varied nonces
        initialNonce = uint48(bound(initialNonce, 0, 50));
        mintAmount = uint208(bound(mintAmount, 1e18, MAX_MINT_AMOUNT));
        numMints = uint8(bound(numMints, 1, 10)); // Test 1-10 mints per beneficiary

        // Calculate total mint amount and ensure it doesn't exceed supply cap
        uint256 totalMintPerBeneficiary = uint256(mintAmount) * uint256(numMints);
        uint256 totalMintBothBeneficiaries = totalMintPerBeneficiary * 2;

        // Skip test if total would exceed supply cap
        vm.assume(totalMintBothBeneficiaries <= APX_SUPPLY_CAP);

        // Set initial nonces for both beneficiaries by consuming dummy orders
        // This simulates prior activity and establishes the starting nonce
        if (initialNonce > 0) {
            for (uint48 i = 0; i < initialNonce; i++) {
                // Create dummy orders to increment nonces
                IMinterV0.Order memory dummyAliceOrder = _createOrder(alice, i, 1e18);
                bytes memory dummyAliceSig = _signOrder(dummyAliceOrder, alicePrivateKey);
                vm.prank(minter);
                bytes32 dummyAliceOpId = minterV0.requestMint(dummyAliceOrder, dummyAliceSig);
                // Clean up dummy order
                vm.prank(guardian);
                minterV0.cancelMint(dummyAliceOpId);

                IMinterV0.Order memory dummyBobOrder = _createOrder(bob, i, 1e18);
                bytes memory dummyBobSig = _signOrder(dummyBobOrder, bobPrivateKey);
                vm.prank(minter);
                bytes32 dummyBobOpId = minterV0.requestMint(dummyBobOrder, dummyBobSig);
                // Clean up dummy order
                vm.prank(guardian);
                minterV0.cancelMint(dummyBobOpId);
            }
        }

        // Verify initial nonces are set correctly
        assertEq(minterV0.nonce(alice), initialNonce, "Alice initial nonce not set correctly");
        assertEq(minterV0.nonce(bob), initialNonce, "Bob initial nonce not set correctly");

        // Arrays to track operation IDs for each beneficiary
        bytes32[] memory aliceOpIds = new bytes32[](numMints);
        bytes32[] memory bobOpIds = new bytes32[](numMints);

        // Request mints for both alice and bob with sequential nonces
        for (uint256 i = 0; i < numMints; i++) {
            uint48 currentNonce = initialNonce + uint48(i);

            // Alice's mint request
            IMinterV0.Order memory aliceOrder = _createOrder(alice, currentNonce, mintAmount);
            bytes memory aliceSig = _signOrder(aliceOrder, alicePrivateKey);

            vm.prank(minter);
            aliceOpIds[i] = minterV0.requestMint(aliceOrder, aliceSig);

            // Bob's mint request
            IMinterV0.Order memory bobOrder = _createOrder(bob, currentNonce, mintAmount);
            bytes memory bobSig = _signOrder(bobOrder, bobPrivateKey);

            vm.prank(minter);
            bobOpIds[i] = minterV0.requestMint(bobOrder, bobSig);

            // Verify nonces incremented correctly
            assertEq(minterV0.nonce(alice), currentNonce + 1, "Alice nonce not incremented correctly after request");
            assertEq(minterV0.nonce(bob), currentNonce + 1, "Bob nonce not incremented correctly after request");
        }

        // Fast forward past delay to make all mints executable
        vm.warp(block.timestamp + MINT_DELAY + 1);

        // Execute all mints for both beneficiaries
        for (uint256 i = 0; i < numMints; i++) {
            // Execute alice's mint
            vm.prank(minter);
            minterV0.executeMint(aliceOpIds[i]);

            // Execute bob's mint
            vm.prank(minter);
            minterV0.executeMint(bobOpIds[i]);
        }

        // Verify final balances
        assertEq(apxUSD.balanceOf(alice), totalMintPerBeneficiary, "Alice did not receive correct total amount");
        assertEq(apxUSD.balanceOf(bob), totalMintPerBeneficiary, "Bob did not receive correct total amount");

        // Verify total supply
        assertEq(apxUSD.totalSupply(), totalMintBothBeneficiaries, "Total supply does not match sum of all mints");

        // Verify final nonces
        uint48 expectedFinalNonce = initialNonce + uint48(numMints);
        assertEq(minterV0.nonce(alice), expectedFinalNonce, "Alice final nonce incorrect");
        assertEq(minterV0.nonce(bob), expectedFinalNonce, "Bob final nonce incorrect");

        // Verify all pending orders were cleaned up
        for (uint256 i = 0; i < numMints; i++) {
            IMinterV0.Order memory aliceOrder = minterV0.pendingOrder(aliceOpIds[i]);
            assertEq(aliceOrder.beneficiary, address(0), "Alice order not cleaned up after execution");

            IMinterV0.Order memory bobOrder = minterV0.pendingOrder(bobOpIds[i]);
            assertEq(bobOrder.beneficiary, address(0), "Bob order not cleaned up after execution");
        }
    }
}
