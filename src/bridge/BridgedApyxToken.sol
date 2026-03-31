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
import {IBridgedToken} from "./IBridgedToken.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts-ccip/interfaces/IGetCCIPAdmin.sol";
import {EInvalidAddress} from "../errors/InvalidAddress.sol";
import {EInvalidCaller} from "../errors/InvalidCaller.sol";
import {ENotImplemented} from "../errors/NotImplemented.sol";
import {ESupplyCapped} from "../errors/SupplyCapped.sol";

/**
 * @title BridgedApyxToken
 * @notice Destination-chain representation of an Apyx token (apxUSD or apyUSD),
 *         bridged via Chainlink CCIP. The same contract source is deployed once per
 *         token per destination chain — token identity is determined by the name/symbol
 *         passed to `initialize`.
 *
 * @dev Deployed on chains other than Ethereum mainnet (e.g. Base).
 *      Uses the BurnMintTokenPool pattern:
 *        - Bridging in:  pool calls mint(to, amount)
 *        - Bridging out: router transfers tokens to pool, pool calls burn(amount)
 *
 *      mint(), burn(uint256), and burnFrom(address,uint256) are gated by the
 *      `onlyCCIPPool` modifier, which performs a single SLOAD against the stored
 *      ccipPool address. This is significantly cheaper than AccessManager's external
 *      call + multiple SLOADs, keeping the three-call sequence (balanceOf +
 *      releaseOrMint + balanceOf) within the CCIP OffRamp's 90k gas budget.
 *
 *      All other privileged functions (pause, setSupplyCap, setCCIPAdmin,
 *      setCCIPPool, upgradeToAndCall) remain gated by AccessManager via `restricted`.
 *
 * Features:
 *   - Supply cap (per-chain limit on bridged supply)
 *   - Pausable (emergency stop for all transfers)
 *   - UUPS upgradeable
 *   - AccessManaged (OZ AccessManager) for admin functions
 *   - ERC20Permit (gasless approvals)
 */
contract BridgedApyxToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20PausableUpgradeable,
    ERC20BurnableUpgradeable,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    IBridgedToken,
    EInvalidAddress,
    EInvalidCaller,
    ENotImplemented,
    ESupplyCapped
{
    /// @custom:storage-location erc7201:apyx.storage.BridgedApyxToken
    struct BridgedApyxTokenStorage {
        /// @notice Maximum total supply allowed on this chain (in wei, 18 decimals)
        uint256 supplyCap;
        /// @notice Address authorised to register and configure the CCIP token pool
        address ccipAdmin;
        /// @notice The CCIP BurnMintTokenPool address — the only address allowed to
        ///         call mint(), burn(uint256), and burnFrom(address,uint256).
        ///         Gated directly in the contract (not via AccessManager) to minimise
        ///         gas overhead on the CCIP OffRamp's hot path.
        address ccipPool;
    }

    // keccak256(abi.encode(uint256(keccak256("apyx.storage.BridgedApyxToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 public constant APYX_STORAGE_LOC = 0xa4f2d86eaa23583a3573bad527a373f5639833698591b895b622137cef00ff00;

    function _getStorage() private pure returns (BridgedApyxTokenStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := APYX_STORAGE_LOC
        }
    }

    /// @notice Restricts a function to the CCIP BurnMintTokenPool only.
    /// @dev Single SLOAD — much cheaper than AccessManager's external call + SLOADs.
    modifier onlyCCIPPool() {
        if (msg.sender != _getStorage().ccipPool) revert InvalidCaller();
        _;
    }

    // ----------------------------------------
    // UUPSUpgradeable
    // ----------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the BridgedApyxToken contract
    /// @param name Token name (e.g. "Bridged Apyx USD" or "Bridged Apyx Yield USD")
    /// @param symbol Token symbol (e.g. "bridgedApxUSD" or "bridgedApyUSD")
    /// @param initialAuthority Address of the AccessManager contract
    /// @param initialSupplyCap Maximum total supply on this chain
    /// @param initialCCIPAdmin Address authorised to register the CCIP token pool with
    ///        ITokenAdminRegistry. Must be non-zero.
    function initialize(
        string memory name,
        string memory symbol,
        address initialAuthority,
        uint256 initialSupplyCap,
        address initialCCIPAdmin
    ) public initializer {
        if (initialAuthority == address(0)) revert InvalidAddress("initialAuthority");
        if (initialSupplyCap == 0) revert InvalidSupplyCap();
        if (initialCCIPAdmin == address(0)) revert InvalidAddress("initialCCIPAdmin");

        __ERC20_init(name, symbol);
        __ERC20Permit_init(name);
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessManaged_init(initialAuthority);

        BridgedApyxTokenStorage storage $ = _getStorage();
        $.supplyCap = initialSupplyCap;
        $.ccipAdmin = initialCCIPAdmin;

        emit SupplyCapUpdated(0, initialSupplyCap);
        emit CCIPAdminUpdated(address(0), initialCCIPAdmin);
    }

    /// @notice Authorizes contract upgrades
    /// @dev Only callable through AccessManager with ADMIN_ROLE
    function _authorizeUpgrade(address) internal override restricted {}

    // ----------------------------------------
    // ERC20Upgradeable
    // ----------------------------------------

    /// @notice Hook called before any token transfer — enforces pause
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);
    }

    // ----------------------------------------
    // IBridgedToken: CCIP pool interface
    // ----------------------------------------

    /// @inheritdoc IBridgedToken
    /// @dev Enforces supply cap. Gated by onlyCCIPPool (single SLOAD).
    function mint(address account, uint256 amount) external onlyCCIPPool {
        BridgedApyxTokenStorage storage $ = _getStorage();
        uint256 currentSupply = totalSupply();
        if (currentSupply + amount > $.supplyCap) {
            revert SupplyCapExceeded(amount, $.supplyCap - currentSupply);
        }
        _mint(account, amount);
    }

    /// @inheritdoc IBridgedToken
    /// @dev Overrides ERC20BurnableUpgradeable.burn. Gated by onlyCCIPPool.
    ///      BurnMintTokenPool receives tokens from the router then calls this to burn its balance.
    function burn(uint256 amount) public override(ERC20BurnableUpgradeable, IBridgedToken) onlyCCIPPool {
        super.burn(amount);
    }

    /// @inheritdoc IBridgedToken
    /// @dev Overrides ERC20BurnableUpgradeable.burnFrom. Gated by onlyCCIPPool.
    ///      Preserves the ERC20 allowance check via super.burnFrom.
    function burnFrom(address account, uint256 amount)
        public
        override(ERC20BurnableUpgradeable, IBridgedToken)
        onlyCCIPPool
    {
        super.burnFrom(account, amount);
    }

    /// @inheritdoc IBridgedToken
    /// @dev Always reverts. Implemented as an IBurnMintERC20 interface stub only.
    ///      Privileged burning without an allowance check is not granted to any caller.
    ///      Use burnFrom(address,uint256) for allowance-based burns,
    ///      or burn(uint256) for the pool to burn its own balance.
    function burn(address, uint256) public restricted {
        revert NotImplemented();
    }

    // ----------------------------------------
    // IBridgedToken: CCIP pool address
    // ----------------------------------------

    /// @inheritdoc IBridgedToken
    function getCCIPPool() external view returns (address) {
        return _getStorage().ccipPool;
    }

    /// @inheritdoc IBridgedToken
    function setCCIPPool(address newPool) external restricted {
        if (newPool == address(0)) revert InvalidAddress("newPool");
        BridgedApyxTokenStorage storage $ = _getStorage();
        address oldPool = $.ccipPool;
        $.ccipPool = newPool;
        emit CCIPPoolUpdated(oldPool, newPool);
    }

    // ----------------------------------------
    // IBridgedToken: CCIP admin
    // ----------------------------------------

    /// @inheritdoc IGetCCIPAdmin
    function getCCIPAdmin() external view returns (address) {
        return _getStorage().ccipAdmin;
    }

    /// @inheritdoc IBridgedToken
    function setCCIPAdmin(address newAdmin) external restricted {
        if (newAdmin == address(0)) revert InvalidAddress("newAdmin");
        BridgedApyxTokenStorage storage $ = _getStorage();
        address oldAdmin = $.ccipAdmin;
        $.ccipAdmin = newAdmin;
        emit CCIPAdminUpdated(oldAdmin, newAdmin);
    }

    // ----------------------------------------
    // IBridgedToken: Supply cap
    // ----------------------------------------

    /// @inheritdoc IBridgedToken
    function supplyCap() external view returns (uint256) {
        return _getStorage().supplyCap;
    }

    /// @inheritdoc IBridgedToken
    function supplyCapRemaining() external view returns (uint256) {
        BridgedApyxTokenStorage storage $ = _getStorage();
        uint256 supply = totalSupply();
        return supply >= $.supplyCap ? 0 : $.supplyCap - supply;
    }

    /// @inheritdoc IBridgedToken
    function setSupplyCap(uint256 newCap) external restricted {
        if (newCap == 0) revert InvalidSupplyCap();
        if (newCap < totalSupply()) revert InvalidSupplyCap();
        BridgedApyxTokenStorage storage $ = _getStorage();
        uint256 oldCap = $.supplyCap;
        $.supplyCap = newCap;
        emit SupplyCapUpdated(oldCap, newCap);
    }

    // ----------------------------------------
    // IBridgedToken: Pausable
    // ----------------------------------------

    /// @inheritdoc IBridgedToken
    function pause() external restricted {
        _pause();
    }

    /// @inheritdoc IBridgedToken
    function unpause() external restricted {
        _unpause();
    }
}
