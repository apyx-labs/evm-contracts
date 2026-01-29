// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {
    AccessManagedUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20FreezeableUpgradable} from "./exts/ERC20FreezeableUpgradable.sol";

/**
 * @title ApxUSD
 * @notice A stablecoin backed by off-chain preferred shares with dividend yields
 * @dev Implements ERC-20 with Permit (EIP-2612), pausability, freezing, and role-based access control
 *
 * Features:
 * - Supply cap to limit total issuance
 * - MINT_STRAT for authorized minting contracts
 * - Pausable for emergency situations
 * - Freezeable addresses for compliance
 * - UUPS upgradeable pattern
 */
contract ApxUSD is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20PausableUpgradeable,
    ERC20BurnableUpgradeable,
    ERC20FreezeableUpgradable,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    /// @custom:storage-location erc7201:apyx.storage.ApxUSD
    struct ApxUSDStorage {
        /// @notice Maximum total supply allowed (in wei, 18 decimals)
        uint256 supplyCap;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.ApxUSD")) - 1)) & ~bytes32(uint256(0xff))
    // OR just storage-location ApxUSD
    bytes32 private constant APXUSD_STORAGE_LOC = 0xd4bd5aaf4064e82ca5c0ebf6f76b7f421377722e7c3f989b53116d58938a1600;

    function _getApxUSDStorage() private pure returns (ApxUSDStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := APXUSD_STORAGE_LOC
        }
    }

    /// @notice Emitted when the supply cap is updated
    event SupplyCapUpdated(uint256 oldCap, uint256 newCap);

    /// @notice Error thrown when minting would exceed the supply cap
    error SupplyCapExceeded(uint256 requestedAmount, uint256 availableCapacity);

    /// @notice Error thrown when setting an invalid supply cap
    error InvalidSupplyCap();

    // ----------------------------------------
    // UUPSUpgradeable
    // ----------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the ApxUSD contract
     * @param initialAuthority Address of the AccessManager contract
     * @param initialSupplyCap Maximum total supply (e.g., 1_000_000e18 for $1M)
     */
    function initialize(string memory name, string memory symbol, address initialAuthority, uint256 initialSupplyCap)
        public
        initializer
    {
        require(initialAuthority != address(0), "authority is zero address");
        require(initialSupplyCap > 0, "supply cap must be positive");

        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __ERC20Pausable_init();
        __AccessManaged_init(initialAuthority);

        // Set initial supply cap
        ApxUSDStorage storage $ = _getApxUSDStorage();
        $.supplyCap = initialSupplyCap;

        emit SupplyCapUpdated(0, initialSupplyCap);
    }

    /**
     * @notice Authorizes contract upgrades
     * @dev Only callable through AccessManager
     */
    function _authorizeUpgrade(address newImplementation) internal override restricted {}

    // ----------------------------------------
    // ERC20Upgradeable
    // ----------------------------------------

    /**
     * @notice Mints new apxUSD tokens
     * @dev Only callable through AccessManager with MINT_STRAT_ROLE
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint (in wei, 18 decimals)
     */
    function mint(address to, uint256 amount) external restricted {
        ApxUSDStorage storage $ = _getApxUSDStorage();

        uint256 newTotalSupply = totalSupply() + amount;
        if (newTotalSupply > $.supplyCap) {
            revert SupplyCapExceeded(amount, $.supplyCap - totalSupply());
        }

        _mint(to, amount);
    }

    /**
     * @notice Hook that is called before any token transfer
     * @dev Enforces pause and freeze functionality
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20FreezeableUpgradable)
    {
        super._update(from, to, value);
    }

    // ----------------------------------------
    // Supply Cap
    // ----------------------------------------

    /**
     * @notice Updates the supply cap
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param newSupplyCap New maximum total supply
     */
    function setSupplyCap(uint256 newSupplyCap) external restricted {
        if (newSupplyCap < totalSupply()) {
            revert InvalidSupplyCap();
        }

        ApxUSDStorage storage $ = _getApxUSDStorage();
        uint256 oldCap = $.supplyCap;
        $.supplyCap = newSupplyCap;

        emit SupplyCapUpdated(oldCap, newSupplyCap);
    }

    /**
     * @notice Returns the current supply cap
     * @return Maximum total supply allowed
     */
    function supplyCap() external view returns (uint256) {
        ApxUSDStorage storage $ = _getApxUSDStorage();
        return $.supplyCap;
    }

    /**
     * @notice Returns the remaining capacity before hitting the supply cap
     * @return Amount of tokens that can still be minted
     */
    function supplyCapRemaining() external view returns (uint256) {
        ApxUSDStorage storage $ = _getApxUSDStorage();
        uint256 supply = totalSupply();
        return supply >= $.supplyCap ? 0 : $.supplyCap - supply;
    }

    // ----------------------------------------
    // ERC20PausableUpgradeable
    // ----------------------------------------

    /**
     * @notice Pauses all token transfers
     * @dev Only callable through AccessManager with ADMIN_ROLE
     */
    function pause() external restricted {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers
     * @dev Only callable through AccessManager with ADMIN_ROLE
     */
    function unpause() external restricted {
        _unpause();
    }

    // ----------------------------------------
    // ERC20FreezeableUpgradeable
    // ----------------------------------------

    /**
     * @notice Freezes an address, preventing transfers to or from it
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param target The address to freeze
     */
    function freeze(address target) external restricted {
        _freeze(target);
    }

    /**
     * @notice Unfreezes an address, allowing transfers to or from it
     * @dev Only callable through AccessManager with ADMIN_ROLE
     * @param target The address to unfreeze
     */
    function unfreeze(address target) external restricted {
        _unfreeze(target);
    }
}
