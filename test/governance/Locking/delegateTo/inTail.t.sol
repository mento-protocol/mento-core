// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { DelegateTo_Locking_Test } from "./Base.t.sol";

contract InTail_DelegateTo_Locking_Test is DelegateTo_Locking_Test {
  function setUp() public override {
    amount = 6300;
    slopePeriod = 7;
    cliff = 0;

    super.setUp();
  }

  function test_delegateTo_shouldReDelegateVotes_toNewDelegate() public {
    vm.roll(block.number + 6 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 199);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 900);
    assertEq(mentoToken.balanceOf(alice), 99100);

    delegate = charlie;

    vm.prank(alice);
    _subject();

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 199);

    vm.roll(block.number + weekInBlocks);

    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }
}
