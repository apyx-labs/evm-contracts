// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApxUSD} from "../ApxUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Deployer} from "./Deployer.sol";

/**
 * @title ApxUSDDeployer
 * @notice Deploys ApxUSD (implementation + proxy) and initializes in a single transaction
 * @dev Non-upgradable; deploy is restricted via AccessManager. Init params are set in the constructor.
 */
contract ApxUSDDeployer is AccessManaged, Deployer {
    /// @notice Token name for the deployed ApxUSD (e.g. "Apyx USD")
    string public name;

    /// @notice Token symbol for the deployed ApxUSD (e.g. "apxUSD")
    string public symbol;

    /// @notice Deny list (AddressList) for the deployed ApxUSD
    address public denyList;

    /// @notice Maximum total supply for the deployed ApxUSD (e.g. 1_000_000e18)
    uint256 public supplyCap;

    /**
     * @notice Sets the AccessManager authority and ApxUSD init params used by deploy()
     * @param _authority Address of the AccessManager contract (used for this deployer and for each deployed ApxUSD)
     * @param _name Token name for the deployed ApxUSD (e.g. "Apyx USD")
     * @param _symbol Token symbol for the deployed ApxUSD (e.g. "apxUSD")
     * @param _supplyCap Maximum total supply for the deployed ApxUSD (e.g. 1_000_000e18)
     */
    constructor(string memory _name, string memory _symbol, address _authority, address _denyList, uint256 _supplyCap)
        AccessManaged(_authority)
    {
        name = _name;
        symbol = _symbol;
        denyList = _denyList;
        supplyCap = _supplyCap;
    }

    /**
     * @notice Deploys ApxUSD implementation, proxy, and initializes in one transaction using constructor params
     * @dev Only callable through AccessManager (restricted)
     * @return proxy The address of the deployed ApxUSD proxy (use this as the stablecoin address)
     */
    function deploy() external restricted returns (address proxy) {
        ApxUSD impl = new ApxUSD();
        bytes memory initData = abi.encodeCall(ApxUSD.initialize, (name, symbol, authority(), denyList, supplyCap));
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(impl), initData);
        proxy = address(proxyContract);

        emit Deployed(proxy, address(impl));
    }
}
