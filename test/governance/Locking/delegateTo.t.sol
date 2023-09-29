// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract DelegateTo_Locking_Test is Locking_Test {
  uint256 public lockId;

  function test_delegateTo_shouldReDelegateVotes_toNewDelegate_inCliff() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 60000, 30, 0);

    _incrementBlock(20 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 6303);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20000);
    assertEq(mentoToken.balanceOf(alice), 80000);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, charlie);

    assertEq(lockingContract.balanceOf(bob), 0);

    assertEq(lockingContract.balanceOf(charlie), 6303);

    _incrementBlock(10 * weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_delegateTo_shouldReDelegateVotes_whenMultipleReDelegates_inCliff() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 60000, 30, 0);

    _incrementBlock(20 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    vm.prank(alice);
    lockingContract.withdraw();

    _incrementBlock(5 * weekInBlocks);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, bob);

    assertEq(lockingContract.balanceOf(bob), 3148);
    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10000);
    assertEq(mentoToken.balanceOf(alice), 90000);

    _incrementBlock(5 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
    assertEq(lockingContract.totalSupply(), 0);
  }

  function test_delegateTo_shouldReDelegateVotes_toNewDelegate_inTail() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 6300, 7, 0);

    _incrementBlock(6 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 199);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 900);
    assertEq(mentoToken.balanceOf(alice), 99100);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, charlie);

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 199);

    _incrementBlock(weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_delegateTo_shouldReDelegateVotes_whenFirstDelegateWasInCliff() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 152747);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 630000);
    assertEq(mentoToken.balanceOf(alice), 370000);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, charlie);

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 152747);

    _incrementBlock(weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 152747);

    _incrementBlock(7 * weekInBlocks);
    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_shouldReDelegateVotes_whenCliffBiggerThan0AfterRedelegate() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(4 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 450000);
    assertEq(mentoToken.balanceOf(alice), 550000);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, charlie);

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 109105);

    _incrementBlock(5 * weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_shouldReDelegateVotes_whenInTail() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(8 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 90000);
    assertEq(mentoToken.balanceOf(alice), 910000);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, charlie);

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 21821);

    _incrementBlock(weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_shouldRevert_whenAfterFinishTime() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(10 * weekInBlocks);

    vm.prank(alice);
    vm.expectRevert("Slope == 0, unacceptable value for slope");
    lockingContract.delegateTo(lockId, charlie);
  }
}
