// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {ApyUSDTest} from "./BaseTest.sol";
import {AddressList} from "../../../src/AddressList.sol";
import {IAddressList} from "../../../src/interfaces/IAddressList.sol";
import {ApyUSD} from "../../../src/ApyUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DenyListEventTest
 * @notice Tests for DenyListUpdated event emission
 */
contract DenyListEventTest is ApyUSDTest {
    // ========================================
    // DenyListUpdated Event Tests
    // ========================================

    /**
     * @notice Test that DenyListUpdated event emits correct old and new addresses
     * @dev Sets an initial deny list A, then calls setDenyList(B)
     *      Asserts the DenyListUpdated event is emitted with (address(A), address(B))
     */
    function test_DenyListUpdated_EmitsCorrectOldAndNewAddresses() public {
        // Create a new deny list (B)
        AddressList denyListB = new AddressList(address(accessManager));

        // Set deny list to B and expect event with (current deny list address, B address)
        vm.prank(admin);
        vm.expectEmit(true, true, false, false);
        emit DenyListUpdated(address(denyList), address(denyListB));
        apyUSD.setDenyList(IAddressList(address(denyListB)));
    }

    /**
     * @notice Test event emission on first set from zero address
     * @dev On a freshly initialized contract, the initial deny list is set during initialization
     *      This test verifies that the initialization emits (address(0), address(A))
     */
    function test_DenyListUpdated_EventOnFirstSetFromZero() public {
        // We need to check the initialization event that was emitted during setUp
        // The ApyUSD contract initialization should emit DenyListUpdated(address(0), initialDenyList)
        // Since we can't check past events easily in Foundry, we'll verify the behavior
        // by checking that a newly deployed contract emits the correct event

        // Create a new deny list
        AddressList newDenyList = new AddressList(address(accessManager));

        // Deploy a new ApyUSD implementation
        ApyUSD newApyUSDImpl = new ApyUSD();

        // Initialize should emit DenyListUpdated(address(0), newDenyList)
        bytes memory initData = abi.encodeCall(
            newApyUSDImpl.initialize,
            ("Test ApyUSD", "testAPY", address(accessManager), address(apxUSD), address(newDenyList))
        );

        // Expect the event during proxy creation (initialization)
        vm.expectEmit(true, true, false, false);
        emit DenyListUpdated(address(0), address(newDenyList));

        // Deploy proxy which will initialize the contract
        new ERC1967Proxy(address(newApyUSDImpl), initData);
    }

    /**
     * @notice Test multiple sequential updates emit correct sequence
     * @dev Set deny list A → B → C
     *      Assert the events are (initial, A), (A, B), (B, C)
     */
    function test_DenyListUpdated_MultipleUpdatesEmitCorrectSequence() public {
        // Create deny lists B and C
        AddressList denyListB = new AddressList(address(accessManager));
        AddressList denyListC = new AddressList(address(accessManager));

        // Current deny list is 'denyList' (set in BaseTest.setUp)
        address initialDenyList = address(denyList);

        vm.startPrank(admin);

        // First update: initial → B
        vm.expectEmit(true, true, false, false);
        emit DenyListUpdated(initialDenyList, address(denyListB));
        apyUSD.setDenyList(IAddressList(address(denyListB)));

        // Second update: B → C
        vm.expectEmit(true, true, false, false);
        emit DenyListUpdated(address(denyListB), address(denyListC));
        apyUSD.setDenyList(IAddressList(address(denyListC)));

        vm.stopPrank();
    }

    // ========================================
    // Event Declaration
    // ========================================

    event DenyListUpdated(address indexed oldDenyList, address indexed newDenyList);
}
