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
 * @dev Like CommitToken, this version is non-transferable for implementation simplicity.
 *      Future versions may support transferability or could be implemented as an NFT
 *      to enable transferring unlocking positions between users.
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
        CommitToken(authority_, asset_, unlockingDelay_, denyList_, type(uint256).max)
    {
        if (vault_ == address(0)) revert InvalidAddress("vault");
        vault = vault_;
    }

    // ========================================
    // Modifiers
    // ========================================

    /**
     * @notice Ensures that only the vault can call the function
     */
    // forge-lint: disable-next-item(unwrapped-modifier-logic)
    modifier onlyVault() {
        if (msg.sender != vault) revert InvalidCaller();
        _;
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

    // ========================================
    // Access Controlled Functions
    // ========================================

    /**
     * @notice Overrides CommitToken _deposit to restrict access to vault only
     * @dev Only the vault can deposit assets into the UnlockToken
     * @param caller The address to deposit from
     * @param receiver The address to deposit to
     * @param assets The amount of assets to deposit
     * @param shares The amount of shares to deposit
     */
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override onlyVault {
        super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Overrides CommitToken _requestRedeem to restrict access to vault only
     * @dev Only the vault can request redeem on behalf of users
     * @param request The redeem request storage pointer
     * @param controller Address that will control the request
     * @param owner Address that owns the shares
     * @param assets Amount of assets to redeem
     * @param shares Amount of shares to redeem
     */
    function _requestRedeem(Request storage request, address controller, address owner, uint256 assets, uint256 shares)
        internal
        override
        onlyVault
    {
        super._requestRedeem(request, controller, owner, assets, shares);
    }
}

