// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { MultipleAccounts_Relock_Locking_Test } from "./Base.t.sol";

contract InCliff_MultipleAccounts_Relock_Locking_Test is MultipleAccounts_Relock_Locking_Test {
  function setUp() public override {
    amount1 = 20;
    slopePeriod1 = 4;
    cliff1 = 2;

    amount2 = 30;
    slopePeriod2 = 3;
    cliff2 = 3;

    amount3 = 40;
    slopePeriod3 = 4;
    cliff3 = 4;

    super.setUp();

    _incrementBlock(2 * weekInBlocks);
  }

  function test_relock_shouldAccountCorrectly_whenMultipleAccounts() public {
    newAmount = 30;
    newSlopePeriod = 6;
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

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 90);
    assertEq(mentoToken.balanceOf(bob), 70);
    assertEq(mentoToken.balanceOf(charlie), 60);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 65);
    assertEq(mentoToken.balanceOf(alice), 95);
    assertEq(mentoToken.balanceOf(bob), 70);
    assertEq(mentoToken.balanceOf(charlie), 70);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 45);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 75);
    assertEq(mentoToken.balanceOf(charlie), 80);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 15);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 85);
    assertEq(mentoToken.balanceOf(charlie), 100);

    _incrementBlock(3 * weekInBlocks);

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
