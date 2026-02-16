// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Test} from "forge-std/src/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ApxUSD} from "../../../src/ApxUSD.sol";
import {MinterV0} from "../../../src/MinterV0.sol";
import {IMinterV0} from "../../../src/interfaces/IMinterV0.sol";
import {Errors} from "../../utils/Errors.sol";
import {Roles} from "../../../src/Roles.sol";
import {MinterTest} from "./BaseTest.sol";

contract MinterV0Test is MinterTest {
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
        vm.expectEmit();
        emit IMinterV0.MaxMintAmountUpdated(MAX_MINT_AMOUNT, newMax);
        minterV0.setMaxMintAmount(newMax);

        assertEq(minterV0.maxMintAmount(), newMax);
    }

    function test_RevertWhen_SetMaxMintSizeWithoutRole() public {
        vm.prank(minter);
        vm.expectRevert();
        minterV0.setMaxMintAmount(20_000e18);
    }

    function test_RevertWhen_SetRateLimitWithZeroPeriod() public {
        uint256 validAmount = 100_000e18;
        uint48 zeroPeriod = 0;

        bytes memory expectedError = Errors.invalidAmount("rateLimitPeriod::zero", zeroPeriod);

        vm.prank(admin);
        vm.expectRevert(expectedError);
        minterV0.setRateLimit(validAmount, zeroPeriod);
    }

    function test_RevertWhen_SetRateLimitWithPeriodTooLong() public {
        uint256 validAmount = 100_000e18;
        uint48 tooLongPeriod = minterV0.MAX_RATE_LIMIT_PERIOD() + 1;

        bytes memory expectedError = Errors.invalidAmount("rateLimitPeriod::tooLong", tooLongPeriod);

        vm.prank(admin);
        vm.expectRevert(expectedError);
        minterV0.setRateLimit(validAmount, tooLongPeriod);
    }
}
