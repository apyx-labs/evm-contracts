// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {VmSafe} from "forge-std/src/Vm.sol";
import {StdCheatsSafe} from "forge-std/src/StdCheats.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Test} from "forge-std/src/Test.sol";
import {BaseTest} from "../BaseTest.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";
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
        for (uint256 i = 0; i < 10; i++) {
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
        if (balance < VERY_SMALL_AMOUNT) vm.assume(false);
        _;
    }

    modifier skipZeroBalance(address token) {
        uint256 balance = IERC20(token).balanceOf(currentActor.addr);
        if (balance == 0) vm.assume(false);
        _;
    }

    function _signMintOrder(IMinterV0.Order memory order, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = minterV0.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
