// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseTest} from "./BaseTest.sol";
import {ApyUSDRateOracle} from "../../../src/oracles/ApyUSDRateOracle.sol";
import {EInvalidAddress} from "../../../src/errors/InvalidAddress.sol";

contract InitializationTest is BaseTest {
    function test_StorageSlot() public pure {
        bytes32 computed =
            keccak256(abi.encode(uint256(keccak256("apyx.storage.ApyUSDRateOracle")) - 1)) & ~bytes32(uint256(0xff));

        assertEq(computed, 0x7c3fd745b6b17d3e08ed287c3401ed4dbb5b9270e485a2fb2e22ca2d91e6e000, "Storage slot mismatch");
    }

    function test_AdjustmentDefault() public view {
        assertEq(oracle.adjustment(), 1e18, "Default adjustment should be 1e18 (neutral)");
    }

    function test_RateEqualsVaultRateAtInit() public view {
        uint256 vaultRate = apyUSD.convertToAssets(1e18);
        assertEq(oracle.rate(), vaultRate, "Rate should equal vault rate at init");
    }

    function test_AuthoritySet() public view {
        assertEq(oracle.authority(), address(accessManager), "Authority should be accessManager");
    }

    function test_RevertWhen_InitializedTwice() public {
        vm.expectRevert();
        oracle.initialize(address(accessManager), address(apyUSD));
    }

    function test_RevertWhen_InitializeWithZeroApyUSD() public {
        ApyUSDRateOracle freshImpl = new ApyUSDRateOracle();
        vm.expectRevert(abi.encodeWithSelector(EInvalidAddress.InvalidAddress.selector, "apyUSD"));
        new ERC1967Proxy(
            address(freshImpl), abi.encodeCall(ApyUSDRateOracle.initialize, (address(accessManager), address(0)))
        );
    }

    function test_RevertWhen_InitializeWithZeroAuthority() public {
        ApyUSDRateOracle freshImpl = new ApyUSDRateOracle();
        vm.expectRevert(abi.encodeWithSelector(EInvalidAddress.InvalidAddress.selector, "initialAuthority"));
        new ERC1967Proxy(address(freshImpl), abi.encodeCall(ApyUSDRateOracle.initialize, (address(0), address(apyUSD))));
    }
}
