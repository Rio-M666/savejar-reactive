// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "reactive-lib-omni/interfaces/ISystemContract.sol";

/// @title MockSystemContract — test double for the Reactive system contract.
/// @notice Etched at the real system contract address (0x8888…8888) in tests, so
///         contracts under test talk to it exactly as they would on Lasna.
///         Records subscriptions and callback requests for assertions.
contract MockSystemContract {
    struct Subscription {
        address subscriber;
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    Subscription[] public subscriptions;
    ISystemContract.CallbackConfiguration_V_1_0[] public callbackRequests;

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        subscriptions.push(Subscription(msg.sender, chainId_, contract_, topic0_, topic1_, topic2_, topic3_));
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function requestCallback(ISystemContract.CallbackVersion, bytes memory) external {}

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        callbackRequests.push(config_);
    }

    function subscriptionCount() external view returns (uint256) {
        return subscriptions.length;
    }

    function callbackCount() external view returns (uint256) {
        return callbackRequests.length;
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    receive() external payable {}
}
