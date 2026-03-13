// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {MinterTest} from "./BaseTest.sol";
import {MinterV0} from "../../../src/MinterV0.sol";
import {Errors} from "../../utils/Errors.sol";

/// @title MinterV0CoverageTest
/// @notice Tests for constructor and setter input validation (Zellic audit coverage gaps)
contract MinterV0CoverageTest is MinterTest {
    function test_RevertWhen_ConstructorWithZeroAuthority() public {
        vm.expectRevert(Errors.invalidAddress("initialAuthority"));
        new MinterV0(address(0), address(apxUSD), MAX_MINT_AMOUNT, RATE_LIMIT_AMOUNT, RATE_LIMIT_PERIOD);
    }

    function test_RevertWhen_ConstructorWithZeroApxUSD() public {
        vm.expectRevert(Errors.invalidAddress("apxUSD"));
        new MinterV0(address(accessManager), address(0), MAX_MINT_AMOUNT, RATE_LIMIT_AMOUNT, RATE_LIMIT_PERIOD);
    }

    function test_RevertWhen_ConstructorWithZeroMaxMintAmount() public {
        vm.expectRevert(Errors.invalidAmount("maxMintAmount", 0));
        new MinterV0(address(accessManager), address(apxUSD), 0, RATE_LIMIT_AMOUNT, RATE_LIMIT_PERIOD);
    }

    function test_RevertWhen_ConstructorWithZeroRateLimitAmount() public {
        vm.expectRevert(Errors.invalidAmount("rateLimitAmount", 0));
        new MinterV0(address(accessManager), address(apxUSD), MAX_MINT_AMOUNT, 0, RATE_LIMIT_PERIOD);
    }

    function test_RevertWhen_ConstructorWithZeroRateLimitPeriod() public {
        vm.expectRevert(Errors.invalidAmount("rateLimitPeriod::zero", 0));
        new MinterV0(address(accessManager), address(apxUSD), MAX_MINT_AMOUNT, RATE_LIMIT_AMOUNT, 0);
    }

    function test_RevertWhen_SetMaxMintAmountWithZero() public {
        vm.prank(admin);
        vm.expectRevert(bytes("MinterV0: max mint amount must be positive"));
        minterV0.setMaxMintAmount(0);
    }

    function test_RevertWhen_SetRateLimitWithZeroAmount() public {
        vm.expectRevert(Errors.invalidAmount("rateLimitAmount", 0));
        vm.prank(admin);
        minterV0.setRateLimit(0, 1 days);
    }
}
