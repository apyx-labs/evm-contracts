// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IAddressList} from "../../src/interfaces/IAddressList.sol";

contract MockAddressList is IAddressList {
    mapping(address => bool) private _denied;
    address[] private _list;

    function add(address user) external {
        if (!_denied[user]) {
            _denied[user] = true;
            _list.push(user);
        }
        emit Added(user);
    }

    function remove(address user) external {
        _denied[user] = false;
        emit Removed(user);
    }

    function contains(address user) external view returns (bool) {
        return _denied[user];
    }

    function length() external view returns (uint256) {
        return _list.length;
    }

    function at(uint256 index) external view returns (address) {
        return _list[index];
    }
}
