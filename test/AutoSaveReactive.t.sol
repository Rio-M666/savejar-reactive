// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {AutoSaveReactive} from "../src/AutoSaveReactive.sol";
import {SaveJar} from "../src/SaveJar.sol";
import {MockSystemContract} from "./mocks/MockSystemContract.sol";
import {ISystemContract} from "reactive-lib-omni/interfaces/ISystemContract.sol";
import {IReactive} from "reactive-lib-omni/interfaces/IReactive.sol";

contract AutoSaveReactiveTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 constant SEPOLIA = 11155111;

    uint256 constant TOPIC0 = uint256(keccak256("Deposit(address,uint256)"));
    MockSystemContract mock;
    SaveJar jar;
    AutoSaveReactive rsc;
    address user = makeAddr("user");

    uint256 constant BPS = 2000; // 20%
    uint256 constant THRESHOLD = 0.01 ether;
    uint256 constant CAP = 0.05 ether;

    function setUp() public {
        mock = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        mock = MockSystemContract(payable(SYSTEM_ADDR));

        jar = new SaveJar(makeAddr("callbackProxy"), 7 days);
        rsc = new AutoSaveReactive(SEPOLIA, SEPOLIA, address(jar), BPS, THRESHOLD, CAP);
    }

    function _log(address from, uint256 amount) internal view returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: SEPOLIA,
            contractAddress: address(jar),
            topic0: TOPIC0,
            topic1: uint256(uint160(from)),
            topic2: 0,
            topic3: 0,
            data: abi.encode(amount),
            blockNumber: block.number,
            opCode: 0,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _react(address from, uint256 amount) internal {
        vm.prank(SYSTEM_ADDR);
        rsc.react(_log(from, amount));
    }

    function test_ConstructorSubscribesToJarDeposits() public view {
        assertEq(mock.subscriptionCount(), 1);
        (address subscriber, uint256 chainId, address contractAddress, uint256 topic0,,,) = mock.subscriptions(0);
        assertEq(subscriber, address(rsc));
        assertEq(chainId, SEPOLIA);
        assertEq(contractAddress, address(jar));
        assertEq(topic0, TOPIC0);
    }

    function test_ReactRejectsNonSystemCaller() public {
        vm.expectRevert();
        rsc.react(_log(user, 1 ether));
    }

    function test_SmallDepositsAccumulateUntilThreshold() public {
        _react(user, 0.02 ether); // cut 0.004
        assertEq(rsc.pendingCut(user), 0.004 ether);
        assertEq(mock.callbackCount(), 0);

        _react(user, 0.02 ether); // pending 0.008
        assertEq(rsc.pendingCut(user), 0.008 ether);
        assertEq(mock.callbackCount(), 0);

        _react(user, 0.02 ether); // pending 0.012 >= threshold -> sweep all of it
        assertEq(rsc.pendingCut(user), 0);
        assertEq(mock.callbackCount(), 1);
        assertEq(rsc.totalSaved(user), 0.012 ether);
        assertEq(rsc.savesExecuted(), 1);
    }

    function test_CallbackPayloadIsWellFormed() public {
        _react(user, 0.1 ether); // cut 0.02 >= threshold -> immediate sweep

        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload) = mock.callbackRequests(0);
        assertEq(chainId, SEPOLIA);
        assertEq(recipient, address(jar));
        assertGe(gasLimit, 100_000); // Reactive minimum

        bytes4 selector;
        address firstArg;
        address userArg;
        uint256 amountArg;
        assembly {
            selector := mload(add(payload, 0x20))
            firstArg := mload(add(payload, 0x24))
            userArg := mload(add(payload, 0x44))
            amountArg := mload(add(payload, 0x64))
        }
        assertEq(selector, bytes4(keccak256("applySave(address,address,uint256)")));
        assertEq(firstArg, address(0)); // network overwrites this with the RVM ID
        assertEq(userArg, user);
        assertEq(amountArg, 0.02 ether);
    }

    function test_DailyCapEnforcedAndResetsNextDay() public {
        _react(user, 1 ether); // 20% would be 0.2, capped at 0.05
        assertEq(rsc.totalSaved(user), CAP);
        assertEq(mock.callbackCount(), 1);

        _react(user, 1 ether); // same day: no room left under the cap
        assertEq(rsc.pendingCut(user), 0);
        assertEq(mock.callbackCount(), 1);

        vm.warp(block.timestamp + 1 days + 1);
        _react(user, 0.1 ether); // new day: cut 0.02 sweeps again
        assertEq(mock.callbackCount(), 2);
        assertEq(rsc.totalSaved(user), CAP + 0.02 ether);
    }

    function test_ForeignLogsIgnored() public {
        IReactive.LogRecord memory wrongTopic = _log(user, 1 ether);
        wrongTopic.topic0 = 12345;
        vm.prank(SYSTEM_ADDR);
        rsc.react(wrongTopic);

        IReactive.LogRecord memory wrongChain = _log(user, 1 ether);
        wrongChain.chainId = 1;
        vm.prank(SYSTEM_ADDR);
        rsc.react(wrongChain);

        IReactive.LogRecord memory wrongContract = _log(user, 1 ether);
        wrongContract.contractAddress = makeAddr("other");
        vm.prank(SYSTEM_ADDR);
        rsc.react(wrongContract);

        assertEq(rsc.pendingCut(user), 0);
        assertEq(mock.callbackCount(), 0);
    }
}
