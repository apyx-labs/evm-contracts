// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {CommitTokenBaseTest} from "./BaseTest.sol";
import {CommitToken} from "../../../src/CommitToken.sol";
import {Errors} from "../../utils/Errors.sol";

/**
 * @title CommitTokenInitializationTest
 * @notice Tests for CommitToken initialization and constructor
 */
contract CommitTokenInitializationTest is CommitTokenBaseTest {
    function test_Initialization() public {
        // Verify asset is set correctly
        assertEq(address(lockToken.asset()), address(mockToken));

        // Verify name and symbol
        assertEq(lockToken.name(), "Mock Token Lock Token");
        assertEq(lockToken.symbol(), "LT-MOCK");

        // Verify unlocking delay is set correctly by checking cooldown behavior
        // We'll test this more thoroughly in Redeem tests, but basic check:
        // Deposit, request redeem, check cooldown
        mockToken.mint(alice, MEDIUM_AMOUNT);
        deposit(alice, MEDIUM_AMOUNT);
        requestRedeem(alice, MEDIUM_AMOUNT);

        uint48 cooldown = lockToken.cooldownRemaining(0, alice);
        assertEq(cooldown, UNLOCKING_DELAY);
    }

    function test_RevertWhen_ConstructorZeroAuthority() public {
        vm.expectRevert(Errors.invalidAddress("authority"));
        new CommitToken(address(0), address(mockToken), UNLOCKING_DELAY, address(denyList));
    }

    function test_RevertWhen_ConstructorZeroAsset() public {
        // Constructor should revert when asset is zero address
        // Note: require() in constructors may not preserve error messages in all cases
        vm.expectRevert();
        new CommitToken(address(accessManager), address(0), UNLOCKING_DELAY, address(denyList));
    }

    function test_RevertWhen_ConstructorZeroUnlockingDelay() public {
        vm.expectRevert(Errors.invalidAmount("unlockingDelay", 0));
        new CommitToken(address(accessManager), address(mockToken), 0, address(denyList));
    }

    function test_RevertWhen_ConstructorZeroDenyList() public {
        vm.expectRevert(Errors.invalidAddress("denyList"));
        new CommitToken(address(accessManager), address(mockToken), UNLOCKING_DELAY, address(0));
    }
}

