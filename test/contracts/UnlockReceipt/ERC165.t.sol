// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {UnlockReceiptBaseTest} from "./BaseTest.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {
    IReceipt,
    IReceiptClaimableAfter,
    IReceiptCancellable,
    IReceiptWithFee
} from "../../../src/interfaces/IReceipt.sol";
import {IUnlockReceipt} from "../../../src/interfaces/IUnlockReceipt.sol";
import {IERC5192} from "../../../src/interfaces/standards/IERC5192.sol";
import {IERC7572} from "../../../src/interfaces/standards/IERC7572.sol";

/**
 * @title UnlockReceiptERC165Test
 * @notice Tests for `UnlockReceipt.supportsInterface`. Asserts each advertised
 *         interface ID resolves to `true` (via the override or via the
 *         inherited `super.supportsInterface`) and that arbitrary unrelated
 *         interface IDs (e.g. `IERC20`, `IERC4626`, a random selector) resolve
 *         to `false`. One test per interface, mirroring the repo convention
 *         in `test/contracts/CommitToken/ERC165.t.sol`.
 */
contract UnlockReceiptERC165Test is UnlockReceiptBaseTest {
    // ============= A. Supported interfaces =============

    /// @notice ERC-165 itself is reported as supported via inherited `super.supportsInterface`.
    function test_SupportsInterface_IERC165() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IERC165).interfaceId), "IERC165");
    }

    /// @notice ERC-721 is reported as supported via inherited `super.supportsInterface`.
    function test_SupportsInterface_IERC721() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IERC721).interfaceId), "IERC721");
    }

    /// @notice ERC-721 metadata extension is reported as supported.
    function test_SupportsInterface_IERC721Metadata() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IERC721Metadata).interfaceId), "IERC721Metadata");
    }

    /// @notice The proposed core `IReceipt` interface is supported.
    function test_SupportsInterface_IReceipt() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IReceipt).interfaceId), "IReceipt");
    }

    /// @notice The proposed `IReceiptClaimableAfter` extension is supported.
    function test_SupportsInterface_IReceiptClaimableAfter() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IReceiptClaimableAfter).interfaceId), "IReceiptClaimableAfter");
    }

    /// @notice The proposed `IReceiptCancellable` extension is intentionally NOT supported by
    ///         the base implementation — cancel lives in the `UnlockReceiptCancellation`
    ///         subclass at `src/unlock/UnlockReceiptCancellation.sol`.
    function test_SupportsInterface_IReceiptCancellable_NotSupported() public view {
        assertFalse(unlockReceipt.supportsInterface(type(IReceiptCancellable).interfaceId), "IReceiptCancellable");
    }

    /// @notice The proposed `IReceiptWithFee` extension is supported.
    function test_SupportsInterface_IReceiptWithFee() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IReceiptWithFee).interfaceId), "IReceiptWithFee");
    }

    /// @notice The Apyx-specific `IUnlockReceipt` surface is supported.
    function test_SupportsInterface_IUnlockReceipt() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IUnlockReceipt).interfaceId), "IUnlockReceipt");
    }

    /// @notice EIP-5192 (soulbound NFT) is supported.
    function test_SupportsInterface_IERC5192() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IERC5192).interfaceId), "IERC5192");
    }

    /// @notice EIP-4906 (metadata-update events) is supported.
    function test_SupportsInterface_IERC4906() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IERC4906).interfaceId), "IERC4906");
    }

    /// @notice EIP-7572 (contract-level metadata URI) is supported.
    function test_SupportsInterface_IERC7572() public view {
        assertTrue(unlockReceipt.supportsInterface(type(IERC7572).interfaceId), "IERC7572");
    }

    // ============= B. Negative cases =============

    /// @notice An arbitrary 4-byte interface ID that the contract does not advertise resolves to `false`.
    function test_DoesNotSupport_RandomInterface() public view {
        assertFalse(unlockReceipt.supportsInterface(0x12345678), "random interfaceId");
    }

    /// @notice `UnlockReceipt` is an ERC-721, not an ERC-20 — `IERC20.interfaceId` resolves to `false`.
    function test_DoesNotSupport_IERC20() public view {
        assertFalse(unlockReceipt.supportsInterface(type(IERC20).interfaceId), "IERC20");
    }

    /// @notice `UnlockReceipt` is not a tokenized vault — `IERC4626.interfaceId` resolves to `false`.
    function test_DoesNotSupport_IERC4626() public view {
        assertFalse(unlockReceipt.supportsInterface(type(IERC4626).interfaceId), "IERC4626");
    }
}
