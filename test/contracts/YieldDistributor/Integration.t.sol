// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseTest} from "../../BaseTest.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";

/**
 * @title YieldDistributor Integration Tests
 * @notice End-to-end tests for minting directly to the YieldDistributor with delegated signing
 */
contract YieldDistributor_IntegrationTest is BaseTest {
    function test_MintToYieldDistributor_EndToEnd() public {
        // 1. Set YieldDistributor signing delegate to alice
        vm.prank(admin);
        yieldDistributor.setSigningDelegate(alice);

        // 2. Create order with YieldDistributor as beneficiary
        uint48 beneficiaryNonce = minterV0.nonce(address(yieldDistributor));
        uint256 orderAmount = SMALL_AMOUNT;
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: address(yieldDistributor),
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 24 hours),
            nonce: beneficiaryNonce,
            amount: uint208(orderAmount)
        });

        // 3. Sign the order using alice's private key (delegate for YieldDistributor)
        bytes32 digest = minterV0.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 4. Confirm that the order is valid (does not revert)
        minterV0.validateOrder(order, signature);

        // 5. Submit the order (minter calls requestMint)
        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);
        assertTrue(operationId != bytes32(0), "Operation ID should be non-zero");

        // 6. Warp past the mint delay and execute
        vm.warp(block.timestamp + MINT_DELAY);
        vm.prank(minter);
        minterV0.executeMint(operationId);

        // 7. Confirm that the YieldDistributor received the funds
        assertEq(
            apxUSD.balanceOf(address(yieldDistributor)),
            orderAmount,
            "YieldDistributor should have received minted amount"
        );
        assertEq(
            yieldDistributor.availableBalance(),
            orderAmount,
            "YieldDistributor availableBalance should match minted amount"
        );
    }
}
