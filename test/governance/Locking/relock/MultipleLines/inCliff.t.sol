// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { MultipleLines_Relock_Locking_Test } from "./Base.t.sol";

contract InCliff_MultipleLines_Relock_Locking_Test is MultipleLines_Relock_Locking_Test {
  function setUp() public override {
    amount1 = 30;
    slopePeriod1 = 3;
    cliff1 = 3;

    amount2 = 50;
    slopePeriod2 = 5;
    cliff2 = 3;

    super.setUp();
  }

  function test_relock_shouldIncreaseAmount_AndContinueReleasingByNewSchedule() public {
    newAmount = 60;
    newSlopePeriod = 6;
    newCliff = 0;
    lockId = lockId2;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 90);
    assertEq(mentoToken.balanceOf(alice), 10);

    _incrementBlock(weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(5 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldIncreaseSlopePeriod_AndContinueReleasingByNewSchedule() public {
    newAmount = 50;
    newSlopePeriod = 10;
    newCliff = 0;
    lockId = lockId1;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 100);
    assertEq(mentoToken.balanceOf(alice), 0);

    _incrementBlock(weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 95);
    assertEq(mentoToken.balanceOf(alice), 5);

    _incrementBlock(9 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldRevert_whenCutCorner() public {
    newAmount = 50;
    newSlopePeriod = 10;
    newCliff = 0;
    lockId = lockId2;

    vm.prank(alice);
    vm.expectRevert("detect cut deposit corner");
    _subject();
  }
}
