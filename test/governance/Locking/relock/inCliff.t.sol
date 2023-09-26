// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Relock_Locking_Test } from "./Base.t.sol";

contract InCliff_Relock_Locking_Test is Relock_Locking_Test {
  function setUp() public override {
    amount = 30;
    slopePeriod = 3;
    cliff = 3;

    super.setUp();
  }

  function test_relock_shouldIncreaseAmount_AndContinueReleasingByNewSchedule() public {
    newAmount = 45;
    newSlopePeriod = 9;
    newCliff = 0;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 45);
    assertEq(mentoToken.balanceOf(alice), 55);

    vm.roll(block.number + 9 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  // TODO: These tests always withdraw after lock expires,
  // it might be usefull to have tests that checks partial expiration
  function test_relock_shouldUpdateSlopeAndCliff_AndContinueReleasingByNewSchedule() public {
    newAmount = 30;
    newSlopePeriod = 3;
    newCliff = 4;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);

    vm.roll(block.number + 7 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldDecreaseSlope_AndContinueReleasingByNewSchedule() public {
    newAmount = 35;
    newSlopePeriod = 18;
    newCliff = 0;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 35);
    assertEq(mentoToken.balanceOf(alice), 65);

    vm.roll(block.number + 18 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldChangeAllParams_whenInCliff_AndContinueReleasingByNewSchedule() public {
    newAmount = 80;
    newSlopePeriod = 16;
    newCliff = 6;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    vm.roll(block.number + 6 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    vm.roll(block.number + 16 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }
}
