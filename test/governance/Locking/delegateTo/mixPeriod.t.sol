// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { DelegateTo_Locking_Test } from "./Base.t.sol";

contract MixPeriod_DelegateTo_Locking_Test is DelegateTo_Locking_Test {
  function setUp() public override {
    amount = 630000;
    slopePeriod = 7;
    cliff = 2;
    aliceBalance = 1000000;

    super.setUp();
  }

  // TODO: this test should be moved to correct place
  function test_delegateTo_shouldReDelegateVotes_whenFirstDelegateWasInCliff() public {
    vm.roll(block.number + weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 152747);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 630000);
    assertEq(mentoToken.balanceOf(alice), 370000);

    delegate = charlie;

    vm.prank(alice);
    _subject();

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 152747);

    vm.roll(block.number + weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 152747);

    vm.roll(block.number + 7 * weekInBlocks);
    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_shouldReDelegateVotes_whenCliffBiggerThan0AfterRedelegate() public {
    vm.roll(block.number + 4 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 450000);
    assertEq(mentoToken.balanceOf(alice), 550000);

    delegate = charlie;

    vm.prank(alice);
    _subject();

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 109105);

    vm.roll(block.number + 5 * weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_shouldReDelegateVotes_whenInTail() public {
    vm.roll(block.number + 8 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 90000);
    assertEq(mentoToken.balanceOf(alice), 910000);

    delegate = charlie;

    vm.prank(alice);
    _subject();

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 21821);

    vm.roll(block.number + weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000000);
  }

  function test_delegateTo_shouldRevert_whenAfterFinishTime() public {
    vm.roll(block.number + 10 * weekInBlocks);

    delegate = charlie;

    vm.prank(alice);
    vm.expectRevert("Slope == 0, unacceptable value for slope");
    _subject();
  }
}
