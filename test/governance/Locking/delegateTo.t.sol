// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract DelegateTo_Locking_Test is Locking_Test {
  uint256 public lockId;

  function test_delegateTo_whenReDelegateToDifferentAccount_shouldDelegateCorrectly() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 60000, 30, 0);

    _incrementBlock(20 * weekInBlocks);

    assertEq(locking.balanceOf(bob), 6303);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 20000);
    assertEq(mentoToken.balanceOf(alice), 80000);

    vm.prank(alice);
    locking.delegateTo(lockId, charlie);

    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.balanceOf(charlie), 6303);

    _incrementBlock(10 * weekInBlocks);

    assertEq(locking.balanceOf(charlie), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_delegateTo_whenRedelegateToSameAccount_shouldDelegateCorrectly() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 60000, 30, 0);

    _incrementBlock(20 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    _incrementBlock(5 * weekInBlocks);

    vm.prank(alice);
    locking.delegateTo(lockId, bob);

    assertEq(locking.balanceOf(bob), 3148);
    assertEq(locking.balanceOf(charlie), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 10000);
    assertEq(mentoToken.balanceOf(alice), 90000);

    _incrementBlock(5 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
    assertEq(locking.totalSupply(), 0);
  }

  function test_delegateTo_whenInTail_shouldReDelegateVotesToNewDelegate() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 6300, 7, 0);

    _incrementBlock(6 * weekInBlocks);

    assertEq(locking.balanceOf(bob), 199);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 900);
    assertEq(mentoToken.balanceOf(alice), 99100);

    vm.prank(alice);
    locking.delegateTo(lockId, charlie);

    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.balanceOf(charlie), 199);

    _incrementBlock(weekInBlocks);

    assertEq(locking.balanceOf(charlie), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_delegateTo_whenInCliff_shouldReDelegateVotes() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(weekInBlocks);

    assertEq(locking.balanceOf(bob), 152747);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 630000);
    assertEq(mentoToken.balanceOf(alice), 370000);

    vm.prank(alice);
    locking.delegateTo(lockId, charlie);

    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.balanceOf(charlie), 152747);

    _incrementBlock(weekInBlocks);

    assertEq(locking.balanceOf(charlie), 152747);

    _incrementBlock(7 * weekInBlocks);
    assertEq(locking.balanceOf(charlie), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_wheninSlope_shouldReDelegateVotes() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(4 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 450000);
    assertEq(mentoToken.balanceOf(alice), 550000);

    vm.prank(alice);
    locking.delegateTo(lockId, charlie);

    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.balanceOf(charlie), 109105);

    _incrementBlock(5 * weekInBlocks);

    assertEq(locking.balanceOf(charlie), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_whenInTail_shouldReDelegateVotes() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(8 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 90000);
    assertEq(mentoToken.balanceOf(alice), 910000);

    vm.prank(alice);
    locking.delegateTo(lockId, charlie);

    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.balanceOf(charlie), 21821);

    _incrementBlock(weekInBlocks);

    assertEq(locking.balanceOf(charlie), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_whenAfterFinishTime_shouldRevert() public {
    mentoToken.mint(alice, 1000000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 630000, 7, 2);

    _incrementBlock(10 * weekInBlocks);

    vm.prank(alice);
    vm.expectRevert("Slope == 0, unacceptable value for slope");
    locking.delegateTo(lockId, charlie);
  }
}
