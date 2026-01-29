// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {MinterTest} from "./BaseTest.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title MinterV0 Order Signing Tests
 * @notice Comprehensive tests for signature malleability protection and EIP-712 hashing including:
 *   - Signature malleability protection (invalid V, flipped S, incorrect length)
 *   - EIP-712 hash consistency verification
 */
contract MinterV0_OrderSigningTest is MinterTest {
    // ----------------------------------------
    // Signature Malleability Tests
    // ----------------------------------------

    function test_RevertWhen_SignatureWithInvalidV() public {
        // Create valid order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes32 digest = minterV0.hashOrder(order);
        (, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        // Modify v to invalid value (not 27 or 28)
        uint8 invalidV = 26;
        bytes memory invalidSignature = abi.encodePacked(r, s, invalidV);

        // Should revert with ECDSAInvalidSignature (OpenZeppelin ECDSA library error)
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignature.selector));
        minterV0.validateOrder(order, invalidSignature);
    }

    function test_RevertWhen_SignatureWithFlippedS() public {
        // Create valid order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes32 digest = minterV0.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        // Create malleable signature by flipping s (using secp256k1 curve order - s)
        bytes32 flippedS =
            bytes32(uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141) - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes memory malleableSignature = abi.encodePacked(r, flippedS, flippedV);

        // Should revert with ECDSAInvalidSignatureS (ECDSA library prevents malleability)
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, flippedS));
        minterV0.validateOrder(order, malleableSignature);
    }

    function test_RevertWhen_SignatureTooShort() public {
        // Create valid order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        // Create signature that's too short (missing v byte)
        bytes memory shortSignature = new bytes(64);

        // Should revert with ECDSAInvalidSignatureLength
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, uint256(64)));
        minterV0.validateOrder(order, shortSignature);
    }

    function test_RevertWhen_SignatureTooLong() public {
        // Create valid order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes32 digest = minterV0.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);

        // Create signature that's too long (extra bytes)
        bytes memory longSignature = abi.encodePacked(r, s, v, bytes1(0x00));

        // Should revert with ECDSAInvalidSignatureLength
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, uint256(66)));
        minterV0.validateOrder(order, longSignature);
    }

    // ----------------------------------------
    // EIP-712 Hash Consistency Tests
    // ----------------------------------------

    function test_HashOrder_ConsistentForSameOrder() public view {
        // Create order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        // Hash twice
        bytes32 hash1 = minterV0.hashOrder(order);
        bytes32 hash2 = minterV0.hashOrder(order);

        // Should be identical
        assertEq(hash1, hash2);
    }

    function test_HashOrder_DifferentForDifferentBeneficiaries() public view {
        // Create two orders with different beneficiaries
        IMinterV0.Order memory order1 = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        IMinterV0.Order memory order2 = IMinterV0.Order({
            beneficiary: bob,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        bytes32 hash1 = minterV0.hashOrder(order1);
        bytes32 hash2 = minterV0.hashOrder(order2);

        // Should be different
        assertTrue(hash1 != hash2);
    }

    function test_HashOrder_DifferentForDifferentAmounts() public view {
        // Create two orders with different amounts
        IMinterV0.Order memory order1 = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        IMinterV0.Order memory order2 = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 2_000e18
        });

        bytes32 hash1 = minterV0.hashOrder(order1);
        bytes32 hash2 = minterV0.hashOrder(order2);

        // Should be different
        assertTrue(hash1 != hash2);
    }

    function test_HashOrder_DifferentForDifferentNonces() public view {
        // Create two orders with different nonces
        IMinterV0.Order memory order1 = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        IMinterV0.Order memory order2 = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 1,
            amount: 1_000e18
        });

        bytes32 hash1 = minterV0.hashOrder(order1);
        bytes32 hash2 = minterV0.hashOrder(order2);

        // Should be different
        assertTrue(hash1 != hash2);
    }

    // ----------------------------------------
    // EIP-712 Compliance Tests
    // ----------------------------------------

    function test_EIP712Compliance_HashOrderReturnsDomainBoundDigest() public view {
        // Create order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        // hashOrder should return the full EIP-712 digest
        bytes32 digest = minterV0.hashOrder(order);

        // Manually compute what the digest should be using structHashOrder
        bytes32 structHash = minterV0.structHashOrder(order);
        bytes32 expectedDigest = keccak256(abi.encodePacked("\x19\x01", minterV0.DOMAIN_SEPARATOR(), structHash));

        // Verify hashOrder returns the full EIP-712 digest
        assertEq(digest, expectedDigest, "hashOrder should return full EIP-712 digest");

        // Verify DOMAIN_SEPARATOR is not zero (contract properly initialized)
        assertTrue(minterV0.DOMAIN_SEPARATOR() != bytes32(0), "Domain separator should be initialized");
    }

    function test_EIP712Compliance_ValidSignatureWithHashOrder() public view {
        // Create order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        // Create EIP-712 compliant signature using hashOrder
        bytes32 digest = minterV0.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should validate successfully (will revert if invalid)
        minterV0.validateOrder(order, signature);
    }

    function test_RevertWhen_SignatureWithoutDomainSeparator() public {
        // Create order
        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: alice,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: 0,
            amount: 1_000e18
        });

        // Create signature WITHOUT domain separator (old, non-compliant way)
        // Sign just the struct hash directly without domain separator
        bytes32 structHash = minterV0.structHashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, structHash);
        bytes memory nonCompliantSignature = abi.encodePacked(r, s, v);

        // Should revert with InvalidSignature because signer won't match
        vm.expectRevert(IMinterV0.InvalidSignature.selector);
        minterV0.validateOrder(order, nonCompliantSignature);
    }
}
