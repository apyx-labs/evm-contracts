// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Chainlink CCIP mock router (from chainlink-ccip dep)
import {MockCCIPRouter} from "@chainlink/contracts-ccip/test/mocks/MockRouter.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/libraries/Client.sol";

// Chainlink CCIP pool contracts
import {BurnMintTokenPool} from "@chainlink/contracts-ccip/pools/BurnMintTokenPool.sol";
import {TokenPool} from "@chainlink/contracts-ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink/contracts-ccip/libraries/Pool.sol";
import {RateLimiter} from "@chainlink/contracts-ccip/libraries/RateLimiter.sol";
// Use the chainlink-ccip IBurnMintERC20 (matches BurnMintTokenPool's import)
import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {IRMN} from "@chainlink/contracts-ccip/interfaces/IRMN.sol";

// Our contracts
import {MockERC20} from "../mocks/MockERC20.sol";
import {BridgedApyxToken} from "../../src/bridge/BridgedApyxToken.sol";
import {IBridgedToken} from "../../src/bridge/IBridgedToken.sol";
import {Roles} from "../../src/Roles.sol";
import {BridgeRoles} from "../../src/bridge/BridgeRoles.sol";

/**
 * @title CCIPBridgeTest
 * @notice Integration tests for BridgedApyxToken + Chainlink CCIP BurnMintTokenPool.
 *
 * @dev Test topology:
 *   "Arbitrum" (source)      — fooUSD (MockERC20) — represents the canonical token
 *   "Base"     (destination) — BridgedApyxToken + BurnMintTokenPool
 *
 * The CCIPLocalSimulator provides a MockCCIPRouter. Note that the mock router performs
 * direct token transfers (safeTransferFrom sender → receiver) and does NOT invoke pool
 * contracts internally. Pool mechanics (burn/mint) are therefore tested by calling
 * lockOrBurn/releaseOrMint directly, simulating the on-ramp/off-ramp behaviour.
 *
 * Key mock router properties used by these tests:
 *   - getOnRamp(chainSelector) → address(1234567890)  — used as the on-ramp caller
 *   - isOffRamp(chainSelector, any) → true             — any address can call releaseOrMint
 *   - getFee(...) → 0                                  — no fees in tests
 */
contract CCIPBridgeTest is Test {
    using Roles for AccessManager;
    using BridgeRoles for AccessManager;

    // ── CCIP infrastructure ───────────────────────────────────────────────
    MockCCIPRouter public mockRouter;
    uint64 public chainSelector;

    // ── Mock RMN proxy ────────────────────────────────────────────────────
    address public rmnProxy;

    // ── Destination side (Base) ───────────────────────────────────────────
    AccessManager public baseAccessManager;
    BridgedApyxToken public bridgedToken;
    BurnMintTokenPool public burnMintPool;

    // ── Source side (Arbitrum — fooUSD) ───────────────────────────────────
    MockERC20 public fooUSD;

    // ── Actors ────────────────────────────────────────────────────────────
    address public admin;
    address public user;

    // ── Fixed mock on-ramp address from MockCCIPRouter.getOnRamp() ────────
    address public constant MOCK_ON_RAMP = address(1234567890);

    // ── Constants ─────────────────────────────────────────────────────────
    uint256 public constant SUPPLY_CAP = 1_000_000e18;
    uint256 public constant BRIDGE_AMOUNT = 1_000e18;

    function setUp() public {
        admin = makeAddr("admin");
        user = makeAddr("user");

        // ── Deploy MockCCIPRouter and set a fixed chain selector ──────────
        // Chain selector mirrors the Sepolia value used in MockCCIPRouter's hardcoded sourceChainSelector.
        chainSelector = 16015286601757825753;
        mockRouter = new MockCCIPRouter();

        // ── Mock RMN proxy — returns isCursed = false for all chains ──────
        rmnProxy = makeAddr("rmnProxy");
        vm.mockCall(rmnProxy, abi.encodeWithSignature("isCursed(bytes16)"), abi.encode(false));

        // ── Deploy fooUSD (source-side mock of apxUSD) ────────────────────
        fooUSD = new MockERC20("fooUSD", "fooUSD");
        vm.label(address(fooUSD), "fooUSD");

        // ── Deploy BridgedApyxToken (destination side) ───────────────────────
        vm.prank(admin);
        baseAccessManager = new AccessManager(admin);

        BridgedApyxToken impl = new BridgedApyxToken();
        bytes memory initData = abi.encodeCall(
            impl.initialize, ("Bridged Apyx USD", "bridgedToken", address(baseAccessManager), SUPPLY_CAP, admin)
        );
        bridgedToken = BridgedApyxToken(address(new ERC1967Proxy(address(impl), initData)));
        vm.label(address(bridgedToken), "BridgedApyxToken");

        // ── Deploy BurnMintTokenPool for BridgedApyxToken ────────────────────
        burnMintPool = new BurnMintTokenPool(
            IBurnMintERC20(address(bridgedToken)),
            18, // localTokenDecimals
            new address[](0), // advancedPoolHooks — none
            rmnProxy,
            address(mockRouter)
        );
        vm.label(address(burnMintPool), "BurnMintTokenPool");

        // ── Set AccessManager admin targets and ccipPool ─────────────────
        vm.startPrank(admin);
        baseAccessManager.setRoleAdmins();
        baseAccessManager.assignAdminTargetsFor(IBridgedToken(address(bridgedToken)));
        bridgedToken.setCCIPPool(address(burnMintPool));
        vm.stopPrank();

        // ── Configure BurnMintTokenPool with remote chain ─────────────────
        // Both source and destination use the same chainSelector in the single-simulator setup.
        // remotePoolAddresses: encode the pool addresses that are authorised on the remote chain.
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(address(burnMintPool)); // self-reference for single-simulator

        TokenPool.ChainUpdate[] memory chainUpdates = new TokenPool.ChainUpdate[](1);
        chainUpdates[0] = TokenPool.ChainUpdate({
            remoteChainSelector: chainSelector,
            remotePoolAddresses: remotePools,
            remoteTokenAddress: abi.encode(address(fooUSD)),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        vm.prank(burnMintPool.owner());
        burnMintPool.applyChainUpdates(new uint64[](0), chainUpdates);

        // ── Mint fooUSD for user ──────────────────────────────────────────
        fooUSD.mint(user, BRIDGE_AMOUNT * 10);
        vm.label(address(mockRouter), "MockCCIPRouter");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Bridge out: pool burns BridgedApyxToken when bridging back to mainnet
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @notice releaseOrMint mints BridgedApyxToken to the receiver.
     * Simulates the CCIP off-ramp delivering tokens to the destination chain.
     */
    function test_releaseOrMint_mintsBridgedApyxToken() public {
        uint256 supplyBefore = bridgedToken.totalSupply();

        Pool.ReleaseOrMintInV1 memory releaseIn = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(user),
            remoteChainSelector: chainSelector,
            receiver: user,
            sourceDenominatedAmount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken),
            sourcePoolAddress: abi.encode(address(burnMintPool)),
            sourcePoolData: "",
            offchainTokenData: ""
        });

        // Any address can call releaseOrMint (mock router's isOffRamp returns true)
        burnMintPool.releaseOrMint(releaseIn);

        assertEq(bridgedToken.balanceOf(user), BRIDGE_AMOUNT, "user should receive bridged tokens");
        assertEq(bridgedToken.totalSupply(), supplyBefore + BRIDGE_AMOUNT, "totalSupply should increase");
    }

    /**
     * @notice lockOrBurn burns BridgedApyxToken held by the pool.
     * Simulates the CCIP on-ramp locking/burning tokens on the source chain.
     */
    function test_lockOrBurn_burnsBridgedApyxToken() public {
        // First mint tokens to the pool (simulates tokens arriving via router.ccipSend)
        _mintToBurnMintPool(BRIDGE_AMOUNT);

        uint256 supplyBefore = bridgedToken.totalSupply();
        assertEq(bridgedToken.balanceOf(address(burnMintPool)), BRIDGE_AMOUNT);

        Pool.LockOrBurnInV1 memory lockIn = Pool.LockOrBurnInV1({
            receiver: abi.encode(user),
            remoteChainSelector: chainSelector,
            originalSender: user,
            amount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken)
        });

        // Must be called as the mock on-ramp address (MockCCIPRouter.getOnRamp returns address(1234567890))
        vm.prank(MOCK_ON_RAMP);
        burnMintPool.lockOrBurn(lockIn);

        assertEq(bridgedToken.balanceOf(address(burnMintPool)), 0, "pool balance should be zero after burn");
        assertEq(bridgedToken.totalSupply(), supplyBefore - BRIDGE_AMOUNT, "totalSupply should decrease");
    }

    /**
     * @notice Full round-trip: bridge in (mint) then bridge back (burn).
     */
    function test_roundTrip_bridgeInThenBack() public {
        // Step 1: bridge in — off-ramp mints BridgedApyxToken to user
        Pool.ReleaseOrMintInV1 memory releaseIn = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(user),
            remoteChainSelector: chainSelector,
            receiver: user,
            sourceDenominatedAmount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken),
            sourcePoolAddress: abi.encode(address(burnMintPool)),
            sourcePoolData: "",
            offchainTokenData: ""
        });

        burnMintPool.releaseOrMint(releaseIn);
        assertEq(bridgedToken.balanceOf(user), BRIDGE_AMOUNT, "round-trip step 1: mint");

        // Step 2: bridge back — user sends BridgedApyxToken to pool, on-ramp burns it
        vm.prank(user);
        bridgedToken.transfer(address(burnMintPool), BRIDGE_AMOUNT);

        Pool.LockOrBurnInV1 memory lockIn = Pool.LockOrBurnInV1({
            receiver: abi.encode(user),
            remoteChainSelector: chainSelector,
            originalSender: user,
            amount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken)
        });

        vm.prank(MOCK_ON_RAMP);
        burnMintPool.lockOrBurn(lockIn);

        assertEq(bridgedToken.balanceOf(user), 0, "round-trip step 2: burn");
        assertEq(bridgedToken.totalSupply(), 0, "supply back to zero after round-trip");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Supply cap enforcement
    // ══════════════════════════════════════════════════════════════════════

    function test_releaseOrMint_revertsWhenSupplyCapExceeded() public {
        // Set supply cap below the bridge amount
        vm.prank(admin);
        bridgedToken.setSupplyCap(BRIDGE_AMOUNT - 1);

        Pool.ReleaseOrMintInV1 memory releaseIn = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(user),
            remoteChainSelector: chainSelector,
            receiver: user,
            sourceDenominatedAmount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken),
            sourcePoolAddress: abi.encode(address(burnMintPool)),
            sourcePoolData: "",
            offchainTokenData: ""
        });

        vm.expectRevert();
        burnMintPool.releaseOrMint(releaseIn);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Pause enforcement
    // ══════════════════════════════════════════════════════════════════════

    function test_releaseOrMint_revertsWhenPaused() public {
        vm.prank(admin);
        bridgedToken.pause();

        Pool.ReleaseOrMintInV1 memory releaseIn = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(user),
            remoteChainSelector: chainSelector,
            receiver: user,
            sourceDenominatedAmount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken),
            sourcePoolAddress: abi.encode(address(burnMintPool)),
            sourcePoolData: "",
            offchainTokenData: ""
        });

        vm.expectRevert();
        burnMintPool.releaseOrMint(releaseIn);
    }

    function test_lockOrBurn_revertsWhenPaused() public {
        _mintToBurnMintPool(BRIDGE_AMOUNT);

        vm.prank(admin);
        bridgedToken.pause();

        Pool.LockOrBurnInV1 memory lockIn = Pool.LockOrBurnInV1({
            receiver: abi.encode(user),
            remoteChainSelector: chainSelector,
            originalSender: user,
            amount: BRIDGE_AMOUNT,
            localToken: address(bridgedToken)
        });

        vm.prank(MOCK_ON_RAMP);
        vm.expectRevert();
        burnMintPool.lockOrBurn(lockIn);
    }

    // ══════════════════════════════════════════════════════════════════════
    // CCIPLocalSimulator — basic ccipSend flow with fooUSD
    // ══════════════════════════════════════════════════════════════════════

    /**
     * @notice Demonstrates CCIPLocalSimulator's ccipSend with fooUSD.
     * MockCCIPRouter transfers tokens directly from sender to receiver (no pool involved).
     * This validates the simulator + MockERC20 setup used as a stand-in for the
     * Arbitrum fooUSD deployment.
     */
    function test_ccipSend_fooUSD_transfersToReceiver() public {
        address receiver = makeAddr("fooUSDReceiver");
        uint256 sendAmount = 500e18;

        fooUSD.mint(user, sendAmount);
        uint256 userBalBefore = fooUSD.balanceOf(user);
        uint256 receiverBalBefore = fooUSD.balanceOf(receiver);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(fooUSD), amount: sendAmount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: address(0), // native fee (0 in mock)
            extraArgs: ""
        });

        // MockCCIPRouter.ccipSend does safeTransferFrom(sender, receiver, amount) directly.
        // No pool or token registration needed for this basic routing test.
        vm.startPrank(user);
        fooUSD.approve(address(mockRouter), sendAmount);
        mockRouter.ccipSend(chainSelector, message);
        vm.stopPrank();

        assertEq(fooUSD.balanceOf(user), userBalBefore - sendAmount, "user fooUSD should decrease");
        assertEq(fooUSD.balanceOf(receiver), receiverBalBefore + sendAmount, "receiver fooUSD should increase");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Access control — only pool can call burn/mint
    // ══════════════════════════════════════════════════════════════════════

    function test_burnMintPool_isSetAsCCIPPool() public view {
        assertEq(bridgedToken.getCCIPPool(), address(burnMintPool), "burnMintPool should be the ccipPool");
    }

    function test_unauthorizedAddress_cannotMintBridgedApyxToken() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        bridgedToken.mint(attacker, BRIDGE_AMOUNT);
    }

    function test_unauthorizedAddress_cannotBurnBridgedApyxToken() public {
        // Set admin as ccipPool temporarily to seed tokens, then restore
        vm.prank(admin);
        bridgedToken.setCCIPPool(admin);
        vm.prank(admin);
        bridgedToken.mint(admin, BRIDGE_AMOUNT);
        vm.prank(admin);
        bridgedToken.setCCIPPool(address(burnMintPool));

        // admin is no longer the pool — burn should revert
        vm.prank(admin);
        vm.expectRevert();
        bridgedToken.burn(BRIDGE_AMOUNT);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Helpers
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Sets admin as ccipPool temporarily to seed pool balance, then restores.
    function _mintToBurnMintPool(uint256 amount) internal {
        vm.prank(admin);
        bridgedToken.setCCIPPool(admin);

        vm.prank(admin);
        bridgedToken.mint(address(burnMintPool), amount);

        vm.prank(admin);
        bridgedToken.setCCIPPool(address(burnMintPool));
    }
}
