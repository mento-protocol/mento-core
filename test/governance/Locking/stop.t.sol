// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract Stop_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 100;
  uint256 public weekInBlocks;

  address public account = alice;
  address public delegate = bob;
  uint96 public amount = 60;
  uint32 public slopePeriod = 30;
  uint32 public cliff = 0;

  function _subject() internal {
    lockingContract.stop();
  }

  function setUp() public override {
    super.setUp();
    _initLocking();
    weekInBlocks = lockingContract.WEEK();

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);
    vm.roll(2 * weekInBlocks + 1);

    vm.prank(alice);
    lockingContract.lock(account, delegate, amount, slopePeriod, cliff);
  }

  function test_stop_shoulRevert_whenNoOwner() public {
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    _subject();
  }

  function test_stop_shouldAccountBalancesCorrectly() public {
    vm.prank(owner);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 60);
    assertEq(mentoToken.balanceOf(alice), 40);
    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.totalSupply(), 0);
  }

  function test_stop_blocksLockCalls() public {
    vm.prank(owner);
    _subject();

    vm.expectRevert("stopped");
    vm.prank(alice);
    lockingContract.lock(account, delegate, amount, slopePeriod, cliff);
  }

  function test_stop_shouldAllowWithdraws() public {
    vm.prank(owner);
    _subject();

    vm.prank(alice);
    lockingContract.withdraw();
  }
}
