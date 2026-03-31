// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {console} from "forge-std/src/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

import {MockCCIPRouter} from "@chainlink/contracts-ccip/test/mocks/MockRouter.sol";
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/pools/BurnMintTokenPool.sol";
import {TokenPool} from "@chainlink/contracts-ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink/contracts-ccip/libraries/Pool.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/libraries/RateLimiter.sol";
import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";

import {BridgeRoles} from "../../src/bridge/BridgeRoles.sol";
import {BridgedApyxToken} from "../../src/bridge/BridgedApyxToken.sol";
import {IBridgedToken} from "../../src/bridge/IBridgedToken.sol";
import {Roles} from "../../src/Roles.sol";

/**
 * @title GasBenchmarkTest
 * @notice Benchmarks the gas cost of the three operations the CCIP OffRamp performs
 *         when delivering a token transfer:
 *
 *           1. balanceOf(receiver)          — pre-transfer snapshot
 *           2. pool.releaseOrMint(...)      — mints to receiver
 *           3. balanceOf(receiver)          — post-transfer snapshot
 *
 *         The OffRamp executes these three calls and the surrounding ERC-165
 *         interface checks within the same transaction. This test verifies that
 *         our token and pool implementation stays well under the practical gas
 *         budget available to token pools in a CCIP message execution.
 *
 *         All storage is cold at the start of each test function (the EVM
 *         access-list resets between setUp and each test call), giving a
 *         realistic worst-case measurement.
 */
contract GasBenchmarkTest is Test {
    using Roles for AccessManager;
    using BridgeRoles for AccessManager;

    // ── CCIP infrastructure ───────────────────────────────────────────────
    MockCCIPRouter public router;
    uint64 public chainSelector;
    address public rmnProxy;

    // ── Contracts under test ──────────────────────────────────────────────
    AccessManager public accessManager;
    BridgedApyxToken public bridgedToken;
    BurnMintTokenPool public pool;

    // ── Actors ────────────────────────────────────────────────────────────
    address public admin;
    address public receiver;

    // ── Constants ─────────────────────────────────────────────────────────
    uint256 public constant SUPPLY_CAP = 1_000_000_000e18;
    uint256 public constant BRIDGE_AMOUNT = 1_000e18;

    /// @notice Gas budget for the first-ever mint on this chain.
    ///         `_totalSupply` and the receiver's `_balances` slot are both zero (cold SSTORE
    ///         0→nonzero, 22,100 gas each), so this is the worst-case measurement.
    ///         Senders initiating the first bridge transfer should set ccipReceiveGasLimit
    ///         to at least this value in their CCIP message extraArgs.
    uint256 public constant MAX_GAS_FIRST_MINT = 120_000;

    /// @notice Gas budget for subsequent mints after the first.
    ///         `_totalSupply` is already non-zero and all contract/pool storage slots are
    ///         warm within the transaction, so the SSTORE and SLOAD costs are significantly
    ///         lower. Only the new receiver's `_balances` slot starts cold.
    uint256 public constant MAX_GAS_SUBSEQUENT_MINT = 90_000;

    function setUp() public {
        admin = makeAddr("admin");
        receiver = makeAddr("receiver");
        chainSelector = 16015286601757825753; // Sepolia chain selector (same as MockCCIPRouter)

        // ── CCIP mock infrastructure ──────────────────────────────────────
        router = new MockCCIPRouter();
        rmnProxy = makeAddr("rmnProxy");
        vm.mockCall(rmnProxy, abi.encodeWithSignature("isCursed(bytes16)"), abi.encode(false));

        // ── Deploy BridgedApyxToken ───────────────────────────────────────
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        BridgedApyxToken impl = new BridgedApyxToken();
        bytes memory initData = abi.encodeCall(
            impl.initialize, ("Bridged Apyx USD", "bridgedApxUSD", address(accessManager), SUPPLY_CAP, admin)
        );
        bridgedToken = BridgedApyxToken(address(new ERC1967Proxy(address(impl), initData)));
        vm.label(address(bridgedToken), "BridgedApyxToken");

        // ── Deploy BurnMintTokenPool ──────────────────────────────────────
        pool = new BurnMintTokenPool(
            IBurnMintERC20(address(bridgedToken)),
            18, // localTokenDecimals
            new address[](0), // advancedPoolHooks
            rmnProxy,
            address(router)
        );
        vm.label(address(pool), "BurnMintTokenPool");

        // ── Configure AccessManager and set real pool ───────────────────────
        vm.startPrank(admin);
        accessManager.setRoleAdmins();
        accessManager.assignAdminTargetsFor(IBridgedToken(address(bridgedToken)));
        bridgedToken.setCCIPPool(address(pool));
        vm.stopPrank();

        // ── Register remote chain on pool ─────────────────────────────────
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(address(pool)); // self-reference for single-simulator

        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: chainSelector,
            remotePoolAddresses: remotePools,
            remoteTokenAddress: abi.encode(address(bridgedToken)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        vm.prank(pool.owner());
        pool.applyChainUpdates(new uint64[](0), chainUpdates);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gas benchmark
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @notice Measures the combined gas consumed by the three calls the CCIP OffRamp
     *         makes per token transfer: balanceOf → releaseOrMint → balanceOf.
     *
     *         Storage is cold at the start of this function (EVM access-list resets
     *         between setUp and the test call), giving a realistic worst-case reading.
     *
     *         Asserts that the total is strictly below MAX_GAS (90,000).
     */
    /**
     * @notice First-ever mint on this chain: both `_totalSupply` and the receiver's
     *         `_balances` slot are zero (cold SSTORE 0→nonzero, 22,100 gas each).
     *         This is the worst-case gas cost. Senders should set ccipReceiveGasLimit
     *         to at least MAX_GAS_FIRST_MINT in their CCIP message extraArgs for the
     *         initial bridge transaction that activates the destination chain.
     */
    function test_gasUsage_firstMint_under120k() public {
        Pool.ReleaseOrMintInV1 memory releaseIn = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(receiver),
            remoteChainSelector: chainSelector,
            receiver: receiver,
            sourceDenominatedAmount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken),
            sourcePoolAddress: abi.encode(address(pool)),
            sourcePoolData: "",
            offchainTokenData: ""
        });

        uint256 gasBefore = gasleft();
        bridgedToken.balanceOf(receiver);
        pool.releaseOrMint(releaseIn);
        bridgedToken.balanceOf(receiver);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used (first mint, cold storage):", gasUsed);
        assertLt(
            gasUsed, MAX_GAS_FIRST_MINT, string.concat("First mint gas exceeds 120k. Measured: ", vm.toString(gasUsed))
        );
    }

    /**
     * @notice Subsequent mint after the chain has been activated: `_totalSupply` is
     *         already non-zero and all contract/pool storage slots are warm within the
     *         transaction. Only the new receiver's `_balances` slot starts cold.
     *         This reflects steady-state bridge usage and must stay under 90k.
     *
     * @dev    Two mints are performed in sequence. The first activates the chain
     *         (initialises _totalSupply), the second measures the warm-state cost
     *         to a fresh receiver address.
     */
    function test_gasUsage_subsequentMint_under90k() public {
        address receiver2 = makeAddr("receiver2");

        // ── First mint: activates the chain, warms contract/pool storage ──
        Pool.ReleaseOrMintInV1 memory firstMint = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(receiver),
            remoteChainSelector: chainSelector,
            receiver: receiver,
            sourceDenominatedAmount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken),
            sourcePoolAddress: abi.encode(address(pool)),
            sourcePoolData: "",
            offchainTokenData: ""
        });
        pool.releaseOrMint(firstMint);

        // ── Second mint: new receiver, warm contract/pool state ───────────
        Pool.ReleaseOrMintInV1 memory secondMint = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(receiver2),
            remoteChainSelector: chainSelector,
            receiver: receiver2,
            sourceDenominatedAmount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken),
            sourcePoolAddress: abi.encode(address(pool)),
            sourcePoolData: "",
            offchainTokenData: ""
        });

        uint256 gasBefore = gasleft();
        bridgedToken.balanceOf(receiver2);
        pool.releaseOrMint(secondMint);
        bridgedToken.balanceOf(receiver2);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used (subsequent mint, warm state):", gasUsed);
        assertLt(
            gasUsed,
            MAX_GAS_SUBSEQUENT_MINT,
            string.concat("Subsequent mint gas exceeds 90k. Measured: ", vm.toString(gasUsed))
        );
    }
}
