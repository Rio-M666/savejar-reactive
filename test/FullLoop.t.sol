// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {AutoSaveReactive} from "../src/AutoSaveReactive.sol";
import {SaveJar} from "../src/SaveJar.sol";
import {MockSystemContract} from "./mocks/MockSystemContract.sol";
import {IReactive} from "reactive-lib-omni/interfaces/IReactive.sol";

/// @title FullLoop — simulates the entire Sepolia → Lasna → Sepolia loop locally.
/// @notice This mirrors, step for step, what the Reactive Network does live:
///         1. user deposits on Sepolia (real `Deposit` event from the real jar)
///         2. the network delivers the log to the reactive contract's `react()`
///         3. the reactive contract requests a callback via the system contract
///         4. the network delivers the callback through the callback proxy,
///            overwriting the payload's first argument with the RVM ID
///         5. the jar moves funds into locked savings — no user transaction
contract FullLoopTest is Test {
    address constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 constant SEPOLIA = 11155111;

    uint256 constant TOPIC0 = uint256(keccak256("Deposit(address,uint256)"));
    MockSystemContract mock;
    SaveJar jar;
    AutoSaveReactive rsc;
    address proxy = makeAddr("callbackProxy");
    address user = makeAddr("user");

    function setUp() public {
        mock = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(mock).code);
        mock = MockSystemContract(payable(SYSTEM_ADDR));

        jar = new SaveJar(proxy, 7 days);
        rsc = new AutoSaveReactive(SEPOLIA, SEPOLIA, address(jar), 2000, 0.01 ether, 0.05 ether);
        jar.setReactiveContract(address(rsc));
        vm.deal(user, 10 ether);
    }

    function test_DepositToLockedSavingsWithoutUserSigningTheSave() public {
        // 1 — the only transaction the user ever signs: the deposit itself.
        vm.prank(user);
        jar.deposit{value: 0.1 ether}();
        assertEq(jar.spendable(user), 0.1 ether);
        assertEq(jar.saved(user), 0);

        // 2 — the network hands the Deposit log to the reactive contract.
        IReactive.LogRecord memory log = IReactive.LogRecord({
            chainId: SEPOLIA,
            contractAddress: address(jar),
            topic0: TOPIC0,
            topic1: uint256(uint160(user)),
            topic2: 0,
            topic3: 0,
            data: abi.encode(0.1 ether),
            blockNumber: block.number,
            opCode: 0,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
        vm.prank(SYSTEM_ADDR);
        rsc.react(log);

        // 3 — a callback was requested: 20% of 0.1 ETH = 0.02 ETH.
        assertEq(mock.callbackCount(), 1);
        (uint256 chainId, address recipient,, bytes memory payload) = mock.callbackRequests(0);
        assertEq(chainId, SEPOLIA);
        assertEq(recipient, address(jar));

        // 4 — the network delivers it via the proxy, injecting the RVM ID
        //     (the reactive contract's address) as the first payload argument.
        bytes memory delivered =
            abi.encodeWithSignature("applySave(address,address,uint256)", address(rsc), user, 0.02 ether);
        // sanity: identical to the requested payload except the injected first arg
        assertEq(payload.length, delivered.length);
        vm.prank(proxy);
        (bool ok,) = address(jar).call(delivered);
        assertTrue(ok);

        // 5 — funds moved into locked savings. The user signed nothing since step 1.
        assertEq(jar.spendable(user), 0.08 ether);
        assertEq(jar.saved(user), 0.02 ether);
        assertEq(jar.unlockTime(user), block.timestamp + 7 days);
    }
}
