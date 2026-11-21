// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {SaveJar} from "../src/SaveJar.sol";

contract SaveJarTest is Test {
    SaveJar jar;
    address proxy = makeAddr("callbackProxy");
    address reactive = makeAddr("reactiveContract");
    address user = makeAddr("user");
    uint256 constant LOCK = 7 days;

    function setUp() public {
        jar = new SaveJar(proxy, LOCK);
        jar.setReactiveContract(reactive);
        vm.deal(user, 10 ether);
    }

    function test_DepositUpdatesSpendableAndEmits() public {
        vm.expectEmit(true, false, false, true, address(jar));
        emit SaveJar.Deposit(user, 1 ether);
        vm.prank(user);
        jar.deposit{value: 1 ether}();
        assertEq(jar.spendable(user), 1 ether);
    }

    function test_PlainTransferIsADeposit() public {
        vm.prank(user);
        (bool ok,) = address(jar).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(jar.spendable(user), 0.5 ether);
    }

    function test_ApplySaveMovesFundsAndLocks() public {
        vm.prank(user);
        jar.deposit{value: 1 ether}();

        vm.prank(proxy);
        jar.applySave(reactive, user, 0.2 ether);

        assertEq(jar.spendable(user), 0.8 ether);
        assertEq(jar.saved(user), 0.2 ether);
        assertEq(jar.unlockTime(user), block.timestamp + LOCK);
    }

    function test_ApplySaveClampsToSpendable() public {
        vm.prank(user);
        jar.deposit{value: 0.05 ether}();

        vm.prank(proxy);
        jar.applySave(reactive, user, 0.08 ether);

        assertEq(jar.saved(user), 0.05 ether);
        assertEq(jar.spendable(user), 0);
    }

    function test_ApplySaveRejectsNonProxy() public {
        vm.expectRevert(SaveJar.NotCallbackProxy.selector);
        jar.applySave(reactive, user, 1);
    }

    function test_ApplySaveRejectsWrongReactive() public {
        vm.prank(proxy);
        vm.expectRevert(SaveJar.NotReactiveContract.selector);
        jar.applySave(makeAddr("impostor"), user, 1);
    }

    function test_WithdrawSpendable() public {
        vm.prank(user);
        jar.deposit{value: 1 ether}();
        uint256 before = user.balance;
        vm.prank(user);
        jar.withdrawSpendable(0.4 ether);
        assertEq(user.balance, before + 0.4 ether);
        assertEq(jar.spendable(user), 0.6 ether);
    }

    function test_WithdrawSavedLockedThenUnlocked() public {
        vm.prank(user);
        jar.deposit{value: 1 ether}();
        vm.prank(proxy);
        jar.applySave(reactive, user, 0.3 ether);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SaveJar.StillLocked.selector, block.timestamp + LOCK));
        jar.withdrawSaved(0.3 ether);

        vm.warp(block.timestamp + LOCK);
        uint256 before = user.balance;
        vm.prank(user);
        jar.withdrawSaved(0.3 ether);
        assertEq(user.balance, before + 0.3 ether);
        assertEq(jar.saved(user), 0);
    }

    function test_SetReactiveContractOnlyOnceAndOnlyOwner() public {
        SaveJar fresh = new SaveJar(proxy, LOCK);
        vm.prank(user);
        vm.expectRevert(SaveJar.NotOwner.selector);
        fresh.setReactiveContract(reactive);

        fresh.setReactiveContract(reactive);
        vm.expectRevert(SaveJar.ReactiveAlreadySet.selector);
        fresh.setReactiveContract(makeAddr("other"));
    }

    function test_PayOnlyFromFeeReserveAndOnlyProxy() public {
        jar.fundFees{value: 0.1 ether}();
        assertEq(jar.feeReserve(), 0.1 ether);

        vm.expectRevert(SaveJar.NotCallbackProxy.selector);
        jar.pay(0.01 ether);

        uint256 before = proxy.balance;
        vm.prank(proxy);
        jar.pay(0.01 ether);
        assertEq(proxy.balance, before + 0.01 ether);
        assertEq(jar.feeReserve(), 0.09 ether);
    }
}
