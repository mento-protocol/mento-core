// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { DelegateTo_Locking_Test } from "./Base.t.sol";

contract InCliff_DelegateTo_Locking_Test is DelegateTo_Locking_Test {
  function setUp() public override {
    amount = 60000;
    slopePeriod = 30;
    cliff = 0;

    super.setUp();
  }

  function test_delegateTo_shouldReDelegateVotes_toNewDelegate() public {
    vm.roll(block.number + 20 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 6303);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20000);
    assertEq(mentoToken.balanceOf(alice), 80000);

    delegate = charlie;

    vm.prank(alice);
    _subject();

    assertEq(lockingContract.balanceOf(bob), 0);

    assertEq(lockingContract.balanceOf(charlie), 6303);

    vm.roll(block.number + 10 * weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_delegateTo_shouldReDelegateVotes_whenMultipleReDelegates() public {
    vm.roll(block.number + 20 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    delegate = charlie;

    vm.prank(alice);
    _subject();

    vm.roll(block.number + 5 * weekInBlocks);

    delegate = bob;

    vm.prank(alice);
    _subject();

    assertEq(lockingContract.balanceOf(bob), 3148);
    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10000);
    assertEq(mentoToken.balanceOf(alice), 90000);

    vm.roll(block.number + 5 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
    assertEq(lockingContract.totalSupply(), 0);
  }
}
