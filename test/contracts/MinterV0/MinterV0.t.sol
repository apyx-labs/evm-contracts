// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {MinterV0} from "../../../src/MinterV0.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";
import {Roles} from "../../../src/Roles.sol";

contract MinterV0Test is Test {
    ApxUSD public apxUSD;
    MinterV0 public minterV0;
    AccessManager public accessManager;

    address public admin = address(0x1);
    address public minter = address(0x2); // Address with MINTER_ROLE
    address public beneficiary;
    uint256 public beneficiaryPrivateKey = 0xB0B;

    uint256 public constant SUPPLY_CAP = 1_000_000e18;
    uint208 public constant MAX_MINT_AMOUNT = 10_000e18;
    uint208 public constant RATE_LIMIT_AMOUNT = 100_000e18; // $100k per period
    uint48 public constant RATE_LIMIT_PERIOD = uint48(1 days); // 24 hours
    uint32 public constant MINT_DELAY = 3600; // 1 hour

    event MaxMintAmountUpdated(uint256 oldMax, uint256 newMax);

    function setUp() public {
        // Set block timestamp to avoid underflow in rate limiting
        vm.warp(365 days);

        beneficiary = vm.addr(beneficiaryPrivateKey);

        // Deploy AccessManager
        vm.prank(admin);
        accessManager = new AccessManager(admin);

        // Deploy ApxUSD
        ApxUSD apxUSDImpl = new ApxUSD();
        bytes memory apxUSDInitData = abi.encodeCall(apxUSDImpl.initialize, (address(accessManager), SUPPLY_CAP));
        ERC1967Proxy apxUSDProxy = new ERC1967Proxy(address(apxUSDImpl), apxUSDInitData);
        apxUSD = ApxUSD(address(apxUSDProxy));

        // Deploy MinterV0
        MinterV0 minterImpl = new MinterV0();
        bytes memory minterInitData = abi.encodeCall(
            minterImpl.initialize,
            (address(accessManager), address(apxUSD), MAX_MINT_AMOUNT, RATE_LIMIT_AMOUNT, RATE_LIMIT_PERIOD)
        );
        ERC1967Proxy minterProxy = new ERC1967Proxy(address(minterImpl), minterInitData);
        minterV0 = MinterV0(address(minterProxy));

        // Configure AccessManager
        vm.startPrank(admin);

        // Set role admins
        accessManager.setRoleAdmin(Roles.MINT_STRAT_ROLE, Roles.ADMIN_ROLE);
        accessManager.setRoleAdmin(Roles.MINTER_ROLE, Roles.ADMIN_ROLE);

        // Grant MINT_STRAT_ROLE to MinterV0 contract (with delay)
        accessManager.grantRole(Roles.MINT_STRAT_ROLE, address(minterV0), MINT_DELAY);

        // Grant MINTER_ROLE to minter address (no delay)
        accessManager.grantRole(Roles.MINTER_ROLE, minter, 0);

        // Configure ApxUSD function permissions
        bytes4 mintSelector = apxUSD.mint.selector;
        bytes4[] memory mintSelectors = new bytes4[](1);
        mintSelectors[0] = mintSelector;
        accessManager.setTargetFunctionRole(address(apxUSD), mintSelectors, Roles.MINT_STRAT_ROLE);

        // Configure MinterV0 function permissions
        bytes4 requestMintSelector = minterV0.requestMint.selector;
        bytes4 executeMintSelector = minterV0.executeMint.selector;
        bytes4 setMaxMintAmountSelector = minterV0.setMaxMintAmount.selector;
        bytes4 setRateLimitSelector = minterV0.setRateLimit.selector;

        bytes4[] memory minterSelectors = new bytes4[](2);
        minterSelectors[0] = requestMintSelector;
        minterSelectors[1] = executeMintSelector;
        accessManager.setTargetFunctionRole(address(minterV0), minterSelectors, Roles.MINTER_ROLE);

        bytes4[] memory adminSelectors = new bytes4[](2);
        adminSelectors[0] = setMaxMintAmountSelector;
        adminSelectors[1] = setRateLimitSelector;
        accessManager.setTargetFunctionRole(address(minterV0), adminSelectors, Roles.ADMIN_ROLE);

        vm.stopPrank();
    }

    function _createOrder(address _beneficiary, uint48 nonce, uint208 amount)
        internal
        view
        returns (IMinterV0.Order memory)
    {
        return IMinterV0.Order({
            beneficiary: _beneficiary,
            notBefore: uint48(block.timestamp),
            notAfter: uint48(block.timestamp + 1 hours),
            nonce: nonce,
            amount: amount
        });
    }

    function _signOrder(IMinterV0.Order memory order, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = minterV0.hashOrder(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_Initialization() public view {
        assertEq(address(minterV0.apxUSD()), address(apxUSD));
        assertEq(minterV0.maxMintAmount(), MAX_MINT_AMOUNT);
        assertEq(minterV0.authority(), address(accessManager));

        // Verify rate limit initialized correctly
        (uint256 amount, uint48 period) = minterV0.rateLimit();
        assertEq(amount, RATE_LIMIT_AMOUNT);
        assertEq(period, RATE_LIMIT_PERIOD);
    }

    function test_SetMaxMintSize() public {
        uint208 newMax = 20_000e18;

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit MaxMintAmountUpdated(MAX_MINT_AMOUNT, newMax);
        minterV0.setMaxMintAmount(newMax);

        assertEq(minterV0.maxMintAmount(), newMax);
    }

    function test_RevertWhen_SetMaxMintSizeWithoutRole() public {
        vm.prank(minter);
        vm.expectRevert();
        minterV0.setMaxMintAmount(20_000e18);
    }

    function test_Upgrade() public {
        // Deploy new implementation
        MinterV0 newImpl = new MinterV0();

        // Upgrade by admin
        vm.prank(admin);
        minterV0.upgradeToAndCall(address(newImpl), "");

        // Verify storage preserved
        assertEq(minterV0.maxMintAmount(), MAX_MINT_AMOUNT);
        assertEq(address(minterV0.apxUSD()), address(apxUSD));
    }

    function test_RevertWhen_UpgradeWithoutRole() public {
        MinterV0 newImpl = new MinterV0();

        vm.prank(minter);
        vm.expectRevert();
        minterV0.upgradeToAndCall(address(newImpl), "");
    }
}
