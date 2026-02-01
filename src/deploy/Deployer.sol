// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

/**
 * @title Deployer
 * @notice Interface for deployer contracts that deploy a proxy and emit on deployment
 */
interface Deployer {
    /// @notice Emitted when a new proxy is deployed
    /// @param proxy The address of the deployed proxy
    /// @param implementation The address of the implementation contract
    event Deployed(address indexed proxy, address indexed implementation);

    /**
     * @notice Deploys a proxy (and implementation if applicable), initializing in one transaction
     * @return proxy The address of the deployed proxy
     */
    function deploy() external returns (address proxy);
}
