// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {MinterV0} from "../../src/MinterV0.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";
import {BaseTest} from "../BaseTest.sol";

contract MintHandler is BaseHandler {
    constructor(address _minter, MinterV0 _minterV0) BaseHandler() {
        minter = _minter;
        minterV0 = _minterV0;
    }

    function mintApxUSDTo(uint256 userIndex, uint208 amount) public {
        Actor memory actor = getActor(userIndex);

        amount = uint208(bound(amount, VERY_SMALL_AMOUNT, SMALL_AMOUNT));
        uint48 nonce = minterV0.nonce(actor.addr);

        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: actor.addr, amount: amount, nonce: nonce, notBefore: 0, notAfter: type(uint48).max
        });

        bytes memory signature = _signMintOrder(order, actor.privateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        skip(MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId);
    }
}
