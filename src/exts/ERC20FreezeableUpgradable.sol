// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC20FreezeableUpgradable is Initializable, ERC20Upgradeable {
    /// @custom:storage-location erc7201:apyx.storage.Freezeable
    struct FreezeableStorage {
        mapping(address => bool) _frozen;
    }

    bytes32 private constant FREEZEABLE_STORAGE_LOC =
        0xe66b3d99be4f71ea7aa9cf2bc9a8a4827bbe4f718fcfa5d183e05f8945211500;

    function _getFreezeableStorage() private pure returns (FreezeableStorage storage $) {
        assembly {
            $.slot := FREEZEABLE_STORAGE_LOC
        }
    }

    /**
     * @dev Emitted when an address is frozen.
     */
    event Frozen(address target);

    /**
     * @dev Emitted when an address is unfrozen.
     */
    event Unfrozen(address target);

    /**
     * @dev The transfer failed because the address transferring from is frozen.
     */
    error FromFrozen();

    /**
     * @dev The transfer failed because the address transferring to is frozen.
     */
    error ToFrozen();

    /**
     * @dev Cannot freeze the zero address.
     */
    error ZeroAddress();

    /**
     * @notice Allows for checking if an address is frozen
     * @param target The address to check
     * @return bool True if the address is frozen
     */
    function isFrozen(address target) public view returns (bool) {
        FreezeableStorage storage $ = _getFreezeableStorage();
        return $._frozen[target];
    }

    /**
     * @notice Freezes an address, stopping transfers to or from the address
     * @param target The address to freeze
     * @dev Emits Frozen(target)
     * @dev Reverts with ZeroAddress if target is address(0)
     * @dev Note: Frozen addresses cannot burn tokens as burning involves transferring to address(0)
     */
    function _freeze(address target) internal virtual {
        if (target == address(0)) {
            revert ZeroAddress();
        }
        FreezeableStorage storage $ = _getFreezeableStorage();
        $._frozen[target] = true;
        emit Frozen(target);
    }

    /**
     * @notice Unfreezes an address, allowing transfers to or from the address
     * @param target The address to unfreeze
     * @dev Emits Unfrozen(target)
     */
    function _unfreeze(address target) internal virtual {
        FreezeableStorage storage $ = _getFreezeableStorage();
        delete $._frozen[target];
        emit Unfrozen(target);
    }

    /**
     * @dev Overrides the default ERC20 _update to enforce freezing
     * @dev Note: This prevents frozen addresses from burning tokens (burning = transfer to address(0))
     * @dev Note: This prevents minting to frozen addresses (minting = transfer from address(0))
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (isFrozen(from)) {
            revert FromFrozen();
        }
        if (isFrozen(to)) {
            revert ToFrozen();
        }
        super._update(from, to, value);
    }
}
