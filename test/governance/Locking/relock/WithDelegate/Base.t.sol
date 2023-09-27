// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "../../Base.t.sol";

contract WithDelegate_Relock_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 100000;

  address public account = alice;
  address public delegate = bob;
  uint96 public amount;
  uint32 public slopePeriod;
  uint32 public cliff;

  uint256 public lockId;
  address public newDelegate;
  uint96 public newAmount;
  uint32 public newSlopePeriod;
  uint32 public newCliff;

  function _subject() internal returns (uint256) {
    return lockingContract.relock(lockId, newDelegate, newAmount, newSlopePeriod, newCliff);
  }

  function setUp() public virtual override {
    super.setUp();
    _initLocking();

    weekInBlocks = uint32(lockingContract.WEEK());

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    _incrementBlock(2 * weekInBlocks + 1);

    amount = 60000;
    slopePeriod = 30;
    cliff = 0;

    vm.prank(alice);
    lockId = lockingContract.lock(account, delegate, amount, slopePeriod, cliff);
  }

  function test_delegate_withoutRelock() public {
    assertEq(lockingContract.balanceOf(bob), 18923);
    assertEq(mentoToken.balanceOf(address(lockingContract)), 60000);
    assertEq(mentoToken.balanceOf(alice), 40000);

    _incrementBlock(29 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 624);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 2000);
    assertEq(mentoToken.balanceOf(alice), 98000);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), aliceBalance);
  }

  function test_relock_accountsDelegatesCorrectly() public {
    _incrementBlock(20 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 6303);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20000);
    assertEq(mentoToken.balanceOf(alice), 80000);

    newAmount = 20000;
    newSlopePeriod = 10;
    newCliff = 0;
    newDelegate = charlie;

    vm.prank(alice);
    _subject();

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 4769);

    _incrementBlock(10 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), aliceBalance);
  }

  function test_relock_reverts_whenUnknownLock() public {
    _incrementBlock(20 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 6303);

    vm.prank(alice);
    lockingContract.withdraw();

    newAmount = 20000;
    newSlopePeriod = 10;
    newCliff = 0;
    newDelegate = charlie;

    lockId = 1337; // does not exist

    vm.expectRevert("caller not a lock owner");
    vm.prank(alice);
    _subject();
  }
}
