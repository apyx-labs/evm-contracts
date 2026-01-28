// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSD} from "src/ApyUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EInsufficientBalance} from "src/errors/InsufficientBalance.sol";
import {Deployer} from "./Deployer.sol";

/**
 * @title ApyUSDDeployer
 * @notice Deploys ApyUSD (implementation + proxy), initializes, deposits deployer's ApxUSD, and sends shares to beneficiary
 * @dev Deploy is restricted via AccessManager. Requires deployer ApxUSD balance > 10_000e18 before deploying.
 */
contract ApyUSDDeployer is AccessManaged, Deployer, EInsufficientBalance {
    /// @notice Minimum ApxUSD balance (in wei, 18 decimals) required on the deployer to call deploy()
    uint256 public constant MIN_APXUSD_BALANCE = 10_000e18;

    /// @notice Token name for the deployed ApyUSD (e.g. "Apyx Yield USD")
    string public name;

    /// @notice Token symbol for the deployed ApyUSD (e.g. "apyUSD")
    string public symbol;

    /// @notice Underlying asset (ApxUSD) address for the deployed vault
    address public asset;

    /// @notice Deny list (AddressList) for the deployed ApyUSD
    address public denyList;

    /// @notice Recipient of ApyUSD shares after the initial deposit
    address public beneficiary;

    /**
     * @notice Sets the AccessManager authority and ApyUSD init params used by deploy()
     * @param _authority Address of the AccessManager contract
     * @param _name Token name for the deployed ApyUSD (e.g. "Apyx Yield USD")
     * @param _symbol Token symbol for the deployed ApyUSD (e.g. "apyUSD")
     * @param _asset Address of the ApxUSD (underlying asset) contract
     * @param _denyList Address of the AddressList (deny list) contract
     * @param _beneficiary Recipient of ApyUSD shares after the initial deposit
     */
    constructor(
        address _authority,
        string memory _name,
        string memory _symbol,
        address _asset,
        address _denyList,
        address _beneficiary
    ) AccessManaged(_authority) {
        name = _name;
        symbol = _symbol;
        asset = _asset;
        denyList = _denyList;
        beneficiary = _beneficiary;
    }

    /**
     * @notice Deploys ApyUSD, deposits deployer's ApxUSD, and sends resulting shares to beneficiary
     * @dev Only callable through AccessManager (restricted). Reverts if deployer ApxUSD balance <= 10_000e18.
     * @return proxy The address of the deployed ApyUSD proxy
     */
    function deploy() external restricted returns (address proxy) {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        if (balance <= MIN_APXUSD_BALANCE) {
            revert InsufficientBalance(address(this), balance, MIN_APXUSD_BALANCE);
        }

        ApyUSD impl = new ApyUSD();
        bytes memory initData = abi.encodeCall(
            ApyUSD.initialize,
            (name, symbol, authority(), asset, denyList)
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(impl), initData);
        proxy = address(proxyContract);

        IERC20(asset).approve(proxy, balance);
        ApyUSD(proxy).deposit(balance, beneficiary);

        emit Deployed(proxy, address(impl));
    }
}
