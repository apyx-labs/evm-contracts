// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseDeploy} from "../BaseDeploy.sol";
import {MinterV0} from "../../src/MinterV0.sol";
import {IMinterV0} from "../../src/interfaces/IMinterV0.sol";
import {console2} from "forge-std/src/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

contract MintOrderBase is BaseDeploy {
    address internal minterV0Address;
    MinterV0 internal minterV0;

    function setUp() internal override {
        super.setUp();

        minterV0Address = deployConfig.get(chainId, "minterV0_address").toAddress();
        vm.label(minterV0Address, "minterV0Address");

        minterV0 = MinterV0(minterV0Address);
    }
}

/**
 * @title CreateMintOrder
 * @notice Creates a mint order for the MinterV0 contract and logs the digest
 * @dev To sign the order, use the following command:
 * ```
 * export SIGNATURE=$(cast wallet sign --account $ACCOUNT --no-hash "$DIGEST")
 * ```
 */
contract CreateOrder is MintOrderBase {
    function run() public {
        super.setUp();

        address beneficiary = vm.envOr("BENEFICIARY", address(0));
        if (beneficiary == address(0)) beneficiary = deployer;
        console2.log("Beneficiary: ", beneficiary);

        uint48 nonce = minterV0.nonce(beneficiary);
        console2.log("Nonce: ", nonce);

        uint256 humanAmount = vm.envOr("AMOUNT", uint256(1000));
        uint256 scaledAmount = humanAmount * 1e18;

        console2.log("Amount:      ", scaledAmount);

        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: beneficiary,
            amount: uint208(scaledAmount),
            nonce: nonce,
            notBefore: 0,
            notAfter: type(uint48).max
        });
        bytes32 digest = minterV0.hashOrder(order);
        console2.log("Digest: ");
        console2.logBytes32(digest);
    }
}

contract SubmitOrder is MintOrderBase {
    bytes internal signature;
    bytes32 internal operationId;

    function run() public {
        super.setUp();

        signature = vm.parseBytes(vm.envString("SIGNATURE"));
        console2.log("Signature:");
        console2.logBytes(signature);

        address beneficiary = vm.envOr("BENEFICIARY", address(0));
        if (beneficiary == address(0)) beneficiary = deployer;
        console2.log("Beneficiary: ", beneficiary);

        uint48 nonce = minterV0.nonce(beneficiary);
        console2.log("Nonce: ", nonce);

        uint256 humanAmount = vm.envOr("AMOUNT", uint256(1000));
        uint256 scaledAmount = humanAmount * 1e18;

        console2.log("Amount:      ", scaledAmount);

        IMinterV0.Order memory order = IMinterV0.Order({
            beneficiary: beneficiary,
            amount: uint208(scaledAmount),
            nonce: nonce,
            notBefore: 0,
            notAfter: type(uint48).max
        });
        minterV0.validateOrder(order, signature);

        vm.startBroadcast(deployer);

        operationId = minterV0.requestMint(order, signature);
        console2.log("Operation ID:");
        console2.logBytes32(operationId);

        address authority = minterV0.authority();
        console2.log("Authority: ", authority);

        IAccessManager accessManager = IAccessManager(authority);
        uint48 scheduleTime = accessManager.getSchedule(operationId);
        console2.log("Schedule time: ", scheduleTime);

        uint48 timeUntilSchedule = scheduleTime - uint48(block.timestamp);
        console2.log("Time until schedule: ", timeUntilSchedule, " seconds");

        vm.stopBroadcast();

        console2.log("\n=== Order Submitted ===");
        console2.log("Operation ID:  ");
        console2.logBytes32(operationId);
    }
}

contract ExecuteOrder is MintOrderBase {
    bytes32 internal operationId;

    address internal apxUSDAddress;
    IERC20 internal apxUSD;
    uint256 internal balanceBefore;

    function run() public {
        super.setUp();

        apxUSDAddress = deployConfig.get(chainId, "apxUSD_address").toAddress();
        vm.label(apxUSDAddress, "apxUSDAddress");

        address beneficiary = vm.envOr("BENEFICIARY", address(0));
        if (beneficiary == address(0)) beneficiary = deployer;
        console2.log("Beneficiary: ", beneficiary);

        apxUSD = IERC20(apxUSDAddress);
        balanceBefore = apxUSD.balanceOf(beneficiary);

        operationId = vm.parseBytes32(vm.envString("OPERATION_ID"));
        console2.log("Operation ID: ");
        console2.logBytes32(operationId);

        address authority = minterV0.authority();
        console2.log("Authority: ", authority);

        IAccessManager accessManager = IAccessManager(authority);
        uint48 scheduleTime = accessManager.getSchedule(operationId);
        console2.log("Schedule time: ", scheduleTime);

        if (block.timestamp < scheduleTime) {
            revert("Order not ready to execute");
        }

        vm.startBroadcast(deployer);

        minterV0.executeMint(operationId);
        console2.log("Mint executed successfully!");

        vm.stopBroadcast();

        console2.log("\n=== Order Summary ===");
        console2.log("Operation ID:");
        console2.logBytes32(operationId);
        console2.log("Balance Before:", balanceBefore);
        console2.log("Balance After:  ", apxUSD.balanceOf(beneficiary));
        console2.log("Balance Change: ", apxUSD.balanceOf(beneficiary) - balanceBefore);
    }
}
