// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { MultipleAccounts_Relock_Locking_Test } from "./Base.t.sol";

contract InTail_MultipleAccounts_Relock_Locking_Test is MultipleAccounts_Relock_Locking_Test {
  function setUp() public override {
    amount1 = 20;
    slopePeriod1 = 4;
    cliff1 = 2;

    amount2 = 32;
    slopePeriod2 = 4;
    cliff2 = 3;

    amount3 = 40;
    slopePeriod3 = 4;
    cliff3 = 4;

    super.setUp();

    _incrementBlock(4 * weekInBlocks);
  }

  function test_relock_shouldAccountCorrectly_whenMultipleAccounts() public {
    newAmount = 22;
    newSlopePeriod = 5;
    newCliff = 1;
    newDelegate = bob;
    lockId = lockId2;

    vm.prank(bob);
    _subject();

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 42);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 78);
    assertEq(mentoToken.balanceOf(charlie), 80);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 32);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 78);
    assertEq(mentoToken.balanceOf(charlie), 90);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 17);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 83);
    assertEq(mentoToken.balanceOf(charlie), 100);

    _incrementBlock(4 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 100);
    assertEq(mentoToken.balanceOf(charlie), 100);
  }
}
