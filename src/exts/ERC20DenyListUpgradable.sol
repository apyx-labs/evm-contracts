// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IAddressList} from "../interfaces/IAddressList.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EDenied} from "../errors/Denied.sol";

abstract contract ERC20DenyListUpgradable is Initializable, ERC20Upgradeable, EInvalidAddress, EDenied {
    /// @custom:storage-location erc7201:apyx.storage.DenyListed
    struct DenyListStorage {
        /// @notice Reference to the AddressList contract for deny list checking
        IAddressList _denyList;
    }

    bytes32 private constant DENYLISTED_STORAGE_LOC =
        0xde333b8ffad3aee9c87bb17db9ab84f10634c83b51f5022e3b2d7da89a012200;

    function _getDenyListStorage() internal pure returns (DenyListStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := DENYLISTED_STORAGE_LOC
        }
    }

    /**
     * @notice Emitted when the deny list contract is updated
     * @param oldDenyList Previous deny list contract address
     * @param newDenyList New deny list contract address
     */
    event DenyListUpdated(address indexed oldDenyList, address indexed newDenyList);

    function __ERC20DenyListedUpgradable_init(IAddressList initialDenyList) internal onlyInitializing {
        if (address(initialDenyList) == address(0)) revert InvalidAddress("initialDenyList");
        DenyListStorage storage $ = _getDenyListStorage();
        $._denyList = initialDenyList;
    }

    function _isDenied(address user) internal view returns (bool) {
        DenyListStorage storage $ = _getDenyListStorage();
        return $._denyList.contains(user);
    }

    function _revertIfDenied(address user) internal view {
        if (_isDenied(user)) revert Denied(user);
    }

    modifier checkNotDenied(address user) {
        _revertIfDenied(user);
        _;
    }

    /**
     * @dev Overrides the default ERC20 _update to enforce deny list checking
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        _revertIfDenied(from);
        _revertIfDenied(to);
        super._update(from, to, value);
    }

    function denyList() public view returns (IAddressList) {
        DenyListStorage storage $ = _getDenyListStorage();
        return $._denyList;
    }

    function _setDenyList(IAddressList newDenyList) internal {
        DenyListStorage storage $ = _getDenyListStorage();
        address oldDenyList = address($._denyList);
        $._denyList = newDenyList;
        emit DenyListUpdated(oldDenyList, address(newDenyList));
    }
}
