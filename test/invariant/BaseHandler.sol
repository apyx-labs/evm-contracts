// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VmSafe} from "forge-std/src/Vm.sol";
import {StdCheatsSafe} from "forge-std/src/StdCheats.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Test} from "forge-std/src/Test.sol";
import {BaseTest} from "../BaseTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StdInvariant} from "forge-std/src/StdInvariant.sol";

abstract contract BaseHandler is BaseTest {
    struct Actor {
        address addr;
        uint256 privateKey;
    }

    Actor[] public actors;
    Actor public currentActor;

    constructor() {
        // Create test users
        for (uint256 i = 0; i < 5; i++) {
            (address addr, uint256 privateKey) = makeAddrAndKey(string.concat("user_", Strings.toString(i)));
            actors.push(Actor({addr: addr, privateKey: privateKey}));
        }
    }

    function setUp() public override {
        // Do not deploy any contracts
    }

    modifier useActor(uint256 index) {
        currentActor = getActor(index);
        _;
    }

    function getActor(uint256 index) internal view returns (Actor memory) {
        return actors[bound(index, 0, actors.length - 1)];
    }

    modifier skipSmallBalance(address token) {
        uint256 balance = IERC20(token).balanceOf(currentActor.addr);
        if (balance < VERY_SMALL_AMOUNT) return;
        _;
    }
}
