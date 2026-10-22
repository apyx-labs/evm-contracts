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
 * @notice Performs the OffRamp's per-transfer calls from inside a contract and measures
 *         gas internally, so the result excludes the transaction-level overhead that
 *         forge's isolate mode would otherwise add to every top-level test call
 *         (21k intrinsic gas, calldata, cold account/storage access per call).
 */
contract OffRampSim {
    BridgedApyxToken public immutable token;
    BurnMintTokenPool public immutable pool;
    uint64 public immutable chainSelector;

    constructor(BridgedApyxToken token_, BurnMintTokenPool pool_, uint64 chainSelector_) {
        token = token_;
        pool = pool_;
        chainSelector = chainSelector_;
    }

    /// @dev Mints `amount` to each receiver in order and returns the gas used per mint.
    function deliver(address[] calldata receivers, uint256 amount) external returns (uint256[] memory gasUsed) {
        gasUsed = new uint256[](receivers.length);
        for (uint256 i = 0; i < receivers.length; i++) {
            Pool.ReleaseOrMintInV1 memory releaseIn = Pool.ReleaseOrMintInV1({
                originalSender: abi.encode(receivers[i]),
                remoteChainSelector: chainSelector,
                receiver: receivers[i],
                sourceDenominatedAmount: amount,
                localToken: address(token),
                sourcePoolAddress: abi.encode(address(pool)),
                sourcePoolData: "",
                offchainTokenData: ""
            });

            uint256 gasBefore = gasleft();
            token.balanceOf(receivers[i]);
            pool.releaseOrMint(releaseIn);
            token.balanceOf(receivers[i]);
            gasUsed[i] = gasBefore - gasleft();
        }
    }
}

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
 *         The calls are made from an `OffRampSim` contract that measures gas internally,
 *         so results are identical whether or not forge runs in isolate mode. Both
 *         mints in a test share one transaction, as they would in a CCIP execution.
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
    OffRampSim public offRamp;

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

        offRamp = new OffRampSim(bridgedToken, pool, chainSelector);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Gas benchmark
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @notice First-ever mint on this chain: both `_totalSupply` and the receiver's
     *         `_balances` slot are zero (cold SSTORE 0→nonzero, 22,100 gas each).
     *         This is the worst-case gas cost. Senders should set ccipReceiveGasLimit
     *         to at least MAX_GAS_FIRST_MINT in their CCIP message extraArgs for the
     *         initial bridge transaction that activates the destination chain.
     *
     * @dev    Measures balanceOf → releaseOrMint → balanceOf inside `OffRampSim`, so the
     *         result excludes per-transaction overhead and is independent of isolate mode.
     */
    function test_gasUsage_firstMint_under120k() public {
        address[] memory receivers = new address[](1);
        receivers[0] = receiver;

        uint256[] memory gasUsed = offRamp.deliver(receivers, BRIDGE_AMOUNT);

        console.log("Gas used (first mint, cold storage):", gasUsed[0]);
        assertLt(
            gasUsed[0],
            MAX_GAS_FIRST_MINT,
            string.concat("First mint gas exceeds 120k. Measured: ", vm.toString(gasUsed[0]))
        );
    }

    /**
     * @notice Subsequent mint after the chain has been activated: `_totalSupply` is
     *         already non-zero and all contract/pool storage slots are warm within the
     *         transaction. Only the new receiver's `_balances` slot starts cold.
     *         This reflects steady-state bridge usage and must stay under 90k.
     *
     * @dev    Both mints run in a single `OffRampSim.deliver` call. The first activates
     *         the chain (initialises _totalSupply) and warms shared storage; the second
     *         is measured for a fresh receiver. Keeping them in one transaction makes the
     *         warm state identical with and without isolate mode.
     */
    function test_gasUsage_subsequentMint_under90k() public {
        address[] memory receivers = new address[](2);
        receivers[0] = receiver;
        receivers[1] = makeAddr("receiver2");

        uint256[] memory gasUsed = offRamp.deliver(receivers, BRIDGE_AMOUNT);

        console.log("Gas used (subsequent mint, warm state):", gasUsed[1]);
        assertLt(
            gasUsed[1],
            MAX_GAS_SUBSEQUENT_MINT,
            string.concat("Subsequent mint gas exceeds 90k. Measured: ", vm.toString(gasUsed[1]))
        );
    }
}
