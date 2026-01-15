// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC7540Operator} from "forge-std/src/interfaces/IERC7540.sol";

import {CommitToken} from "./CommitToken.sol";
import {IUnlockToken} from "./interfaces/IUnlockToken.sol";

/**
 * @title UnlockToken
 * @notice CommitToken subclass that allows a vault to initiate redeem requests on behalf of users
 * @dev The vault address is immutable and set at construction. The vault can act as an operator
 *      for any controller, enabling it to initiate redeem requests automatically.
 */
contract UnlockToken is CommitToken, IUnlockToken {
    /// @notice The vault address that can act as an operator (immutable)
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    address public immutable vault;

    /**
     * @notice Constructs the UnlockToken contract
     * @param authority_ Address of the AccessManager contract
     * @param asset_ Address of the underlying asset token
     * @param vault_ Address of the vault that can act as an operator (immutable)
     * @param unlockingDelay_ Cooldown period for redeem requests in seconds
     * @param denyList_ Address of the AddressList contract for deny list checking
     */
    constructor(address authority_, address asset_, address vault_, uint48 unlockingDelay_, address denyList_)
        CommitToken(authority_, asset_, unlockingDelay_, denyList_)
    {
        if (vault_ == address(0)) revert InvalidAddress("vault");
        vault = vault_;
    }

    /**
     * @notice Returns the token name: "{VaultName} Unlock Token"
     * @return The token name
     * @dev Overrides CommitToken's name() which returns "{AssetName} Commit Token"
     */
    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat(IERC20Metadata(asset()).name(), " Unlock Token");
    }

    /**
     * @notice Returns the token symbol: "{AssetSymbol}unlock"
     * @return The token symbol
     * @dev Overrides CommitToken's symbol() which returns "CT-{AssetSymbol}"
     */
    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return string.concat(IERC20Metadata(asset()).symbol(), "_unlock");
    }

    /**
     * @notice Returns true if the operator is the controller or the vault
     * @param controller The controller address
     * @param operator The operator address to check
     * @return true if operator is controller or vault, false otherwise
     */
    function isOperator(address controller, address operator)
        public
        view
        override(CommitToken, IERC7540Operator)
        returns (bool)
    {
        return controller == operator || operator == vault;
    }
}

