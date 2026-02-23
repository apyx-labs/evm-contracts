// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {BaseHandler} from "./BaseHandler.sol";
import {MinterV0} from "../../src/MinterV0.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";

contract MintHandler is BaseHandler {
    uint256 public ghost_totalMintedToUsers;
    bytes32[] public ghost_pendingOrderIds;

    constructor(address _minter, address _minterGuardian, MinterV0 _minterV0) {
        minter = _minter;
        minterGuardian = _minterGuardian;
        minterV0 = _minterV0;
    }

    function requestMint(uint256 actorIndex, uint208 amount) public {
        Actor memory actor = getActor(actorIndex);
        amount = uint208(bound(amount, VERY_SMALL_AMOUNT, SMALL_AMOUNT));

        uint48 nonce = minterV0.nonce(actor.addr);

        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: actor.addr,
            amount: amount,
            nonce: nonce,
            notBefore: 0,
            notAfter: type(uint48).max
        });

        bytes memory signature = _signMintOrder(order, actor.privateKey);

        vm.prank(minter);
        bytes32 operationId = minterV0.requestMint(order, signature);

        ghost_pendingOrderIds.push(operationId);
    }

    function executeMint(uint256 orderIndex) public {
        if (ghost_pendingOrderIds.length == 0) return;

        orderIndex = bound(orderIndex, 0, ghost_pendingOrderIds.length - 1);
        bytes32 operationId = ghost_pendingOrderIds[orderIndex];

        IMinterV0.Order memory order = minterV0.pendingOrder(operationId);
        if (order.beneficiary == address(0)) {
            _removeOrder(orderIndex);
            return;
        }

        skip(MINT_DELAY + 1);

        vm.prank(minter);
        minterV0.executeMint(operationId);

        ghost_totalMintedToUsers += order.amount;
        _removeOrder(orderIndex);
    }

    function cancelMint(uint256 orderIndex) public {
        if (ghost_pendingOrderIds.length == 0) return;

        orderIndex = bound(orderIndex, 0, ghost_pendingOrderIds.length - 1);
        bytes32 operationId = ghost_pendingOrderIds[orderIndex];

        IMinterV0.Order memory order = minterV0.pendingOrder(operationId);
        if (order.beneficiary == address(0)) {
            _removeOrder(orderIndex);
            return;
        }

        vm.prank(minterGuardian);
        minterV0.cancelMint(operationId);

        _removeOrder(orderIndex);
    }

    function _removeOrder(uint256 index) internal {
        ghost_pendingOrderIds[index] = ghost_pendingOrderIds[ghost_pendingOrderIds.length - 1];
        ghost_pendingOrderIds.pop();
    }
}
