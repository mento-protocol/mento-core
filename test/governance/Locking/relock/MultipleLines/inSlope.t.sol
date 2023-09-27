// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { MultipleLines_Relock_Locking_Test } from "./Base.t.sol";

contract InSlope_MultipleLines_Relock_Locking_Test is MultipleLines_Relock_Locking_Test {
  function setUp() public override {
    amount1 = 30;
    slopePeriod1 = 3;
    cliff1 = 0;

    amount2 = 30;
    slopePeriod2 = 3;
    cliff2 = 0;

    super.setUp();
  }

  function test_relock_shouldUpdateParams_AndContinueReleasingByNewSchedule_whenTransferNeeded() public {
    newAmount = 60;
    newSlopePeriod = 12;
    newCliff = 0;
    lockId = lockId2;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 70);
    assertEq(mentoToken.balanceOf(alice), 30);

    _incrementBlock(weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 55);
    assertEq(mentoToken.balanceOf(alice), 45);

    _incrementBlock(11 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldUpdateParams_AndContinueReleasingByNewSchedule_whenTransferNotNeeded() public {
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20);
    assertEq(mentoToken.balanceOf(alice), 80);

    newAmount = 60;
    newSlopePeriod = 12;
    newCliff = 0;
    lockId = lockId2;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 70);
    assertEq(mentoToken.balanceOf(alice), 30);

    _incrementBlock(weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 55);
    assertEq(mentoToken.balanceOf(alice), 45);

    _incrementBlock(11 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }
}
