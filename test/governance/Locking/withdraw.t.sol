// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract Withdraw_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 100;
  uint256 public weekInBlocks;

  address public account = alice;
  address public delegate = alice;
  uint96 public amount = 30;
  uint32 public slopePeriod;
  uint32 public cliff;

  function _lock() internal returns (uint256) {
    return lockingContract.lock(account, delegate, amount, slopePeriod, cliff);
  }

  function _subject() internal {
    lockingContract.withdraw();
  }

  function setUp() public override {
    super.setUp();
    _initLocking();

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), aliceBalance);

    weekInBlocks = lockingContract.WEEK();

    vm.roll(2 * weekInBlocks + 1);
  }

  function test_withdraw_shouldReleaseCorrectAmount_whenInCliff() public {
    slopePeriod = 3;
    cliff = 3;

    vm.prank(alice);
    _lock();

    vm.roll(block.number + 3 * weekInBlocks);

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);

    vm.roll(block.number + weekInBlocks);

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20);
    assertEq(mentoToken.balanceOf(alice), 80);
  }

  // This test looks redundant, keeping it for the sake of wholeness
  function test_withdraw_shouldNotAffect_whenCalledFromAnotherAccount() public {
    slopePeriod = 3;
    cliff = 0;

    vm.prank(alice);
    _lock();

    vm.roll(block.number + weekInBlocks);

    vm.prank(bob);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
  }

  function test_withdraw_shouldNotReleaseTokens_whenTheLockIsDedicatedToSomeoneElse() public {
    slopePeriod = 3;
    cliff = 0;
    account = bob;
    delegate = bob;

    vm.prank(alice);
    _lock();

    vm.roll(block.number + weekInBlocks);

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
  }

  function test_withdraw_shouldReleaseTokens_whenCalledByTheOwnerOfTheLock() public {
    slopePeriod = 3;
    cliff = 0;
    account = bob;
    delegate = bob;

    vm.prank(alice);
    _lock();

    vm.roll(block.number + weekInBlocks);

    vm.prank(bob);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20);
    assertEq(mentoToken.balanceOf(alice), 70);
    assertEq(mentoToken.balanceOf(bob), 10);
  }
}
