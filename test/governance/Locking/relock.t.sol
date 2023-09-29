// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract Relock_Locking_Test is Locking_Test {
  uint256 public lockId;

  function test_relock_shouldIncreaseAmount_AndContinueReleasingByNewSchedule_inCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.relock(lockId, alice, 45, 9, 0);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 45);
    assertEq(mentoToken.balanceOf(alice), 55);

    _incrementBlock(9 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldUpdateCliff_AndContinueReleasingByNewSchedule_inCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.relock(lockId, alice, 30, 3, 4);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);

    _incrementBlock(7 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldDecreaseSlope_AndContinueReleasingByNewSchedule_inCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.relock(lockId, alice, 35, 18, 0);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 35);
    assertEq(mentoToken.balanceOf(alice), 65);

    _incrementBlock(18 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldChangeAllParams_andContinueReleasingByNewSchedule_inCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.relock(lockId, alice, 80, 16, 6);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(6 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(16 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_shouldChangeAllParams_AndContinueReleasingByNewSchedule_inSlope() public {
    mentoToken.mint(alice, 100);

    vm.startPrank(alice);
    lockId = lockingContract.lock(alice, alice, 30, 3, 0);
    _incrementBlock(2 * weekInBlocks);

    lockingContract.relock(lockId, alice, 80, 16, 6);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(6 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(16 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }

  function test_relock_shouldReleaseBySameSchedule_whenWithdrawBeforeRelock_inSlope() public {
    mentoToken.mint(alice, 100);

    vm.startPrank(alice);
    lockId = lockingContract.lock(alice, alice, 30, 3, 0);
    _incrementBlock(2 * weekInBlocks);

    lockingContract.relock(lockId, alice, 80, 16, 6);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(6 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(16 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }

  function test_relock_shouldChangeAllParams_AndContinueReleasingByNewSchedule_inTail() public {
    mentoToken.mint(alice, 100);

    vm.startPrank(alice);
    lockId = lockingContract.lock(alice, alice, 37, 4, 3);

    _incrementBlock(6 * weekInBlocks);

    lockingContract.relock(lockId, alice, 10, 2, 2);

    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    _incrementBlock(2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    _incrementBlock(2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }

  function test_relock_shouldChangeAllParams_AndTransferMoreTokensToRelock_inTail() public {
    mentoToken.mint(alice, 100);

    vm.startPrank(alice);
    lockId = lockingContract.lock(alice, alice, 37, 4, 3);

    _incrementBlock(6 * weekInBlocks);

    lockingContract.relock(lockId, alice, 10, 2, 2);

    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    _incrementBlock(2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    _incrementBlock(2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }

  function test_relock_shouldRevert_whenAmountLessThanNow() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 38, 4, 3);
    _incrementBlock(6 * weekInBlocks);

    vm.expectRevert("Impossible to relock: less amount, then now is");
    vm.prank(alice);
    lockingContract.relock(lockId, alice, 5, 1, 1);
  }

  function test_relock_shouldRevert_whenPeriodTooShort() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("new line period lock too short");
    vm.prank(alice);
    lockingContract.relock(lockId, alice, 5, 1, 1);
  }

  function test_relock_shouldRevert_whenAmountIsZero() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("zero amount");
    vm.prank(alice);
    lockingContract.relock(lockId, alice, 0, 5, 1);
  }

  function test_relock_shouldRevert_whenSlopeIsZero() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("slope period equal 0");
    vm.prank(alice);
    lockingContract.relock(lockId, alice, 60, 0, 2);
  }

  function test_relock_shouldRevert_whenCliffIsLong() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("cliff too big");
    vm.prank(alice);
    lockingContract.relock(lockId, alice, 60, 12, 105);
  }

  function test_relock_shouldRevert_whenSlopeIsLong() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("slope period too big");
    vm.prank(alice);
    lockingContract.relock(lockId, alice, 60, 210, 10);
  }

  function test_delegate_withoutRelock() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 60000, 30, 0);

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
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_relock_accountsDelegatesCorrectly() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 60000, 30, 0);

    _incrementBlock(20 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 6303);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20000);
    assertEq(mentoToken.balanceOf(alice), 80000);

    vm.prank(alice);
    lockingContract.relock(lockId, charlie, 20000, 10, 0);

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 4769);

    _incrementBlock(10 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 0);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_relock_reverts_whenUnknownLock() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = lockingContract.lock(alice, bob, 60000, 30, 0);

    _incrementBlock(20 * weekInBlocks);

    assertEq(lockingContract.balanceOf(bob), 6303);

    vm.prank(alice);
    lockingContract.withdraw();

    lockId = 1337; // does not exist

    vm.expectRevert("caller not a lock owner");
    vm.prank(alice);
    lockingContract.relock(lockId, charlie, 20000, 10, 0);
  }

  function test_relock_shouldIncreaseAmount_AndContinueReleasingByNewSchedule_whenMultiLines_inCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    uint256 lockId1 = lockingContract.lock(alice, alice, 30, 3, 3);

    vm.prank(alice);
    uint256 lockId2 = lockingContract.lock(alice, alice, 50, 5, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.relock(lockId2, alice, 60, 6, 0);

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

  function test_relock_shouldIncreaseSlopePeriod_AndContinueReleasingByNewSchedul_whenMultiLines_inCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    uint256 lockId1 = lockingContract.lock(alice, alice, 30, 3, 3);

    vm.prank(alice);
    uint256 lockId2 = lockingContract.lock(alice, alice, 50, 5, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.relock(lockId1, alice, 50, 10, 0);

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
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    uint256 lockId1 = lockingContract.lock(alice, alice, 30, 3, 3);

    vm.prank(alice);
    uint256 lockId2 = lockingContract.lock(alice, alice, 50, 5, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    vm.expectRevert("detect cut deposit corner");
    lockingContract.relock(lockId2, alice, 50, 10, 0);
  }

  function test_relock_shouldUpdateParams_AndContinueReleasingByNewSchedule_multiLinesAndTransferNeeded_inSlope()
    public
  {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    uint256 lockId1 = lockingContract.lock(alice, alice, 30, 3, 0);

    vm.prank(alice);
    uint256 lockId2 = lockingContract.lock(alice, alice, 30, 3, 0);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.relock(lockId2, alice, 60, 12, 0);

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

  function test_relock_shouldUpdateParams_AndContinueReleasingByNewSchedule_whenTransferNotNeeded_inSlope() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    uint256 lockId1 = lockingContract.lock(alice, alice, 30, 3, 0);

    vm.prank(alice);
    uint256 lockId2 = lockingContract.lock(alice, alice, 30, 3, 0);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20);
    assertEq(mentoToken.balanceOf(alice), 80);

    vm.prank(alice);
    lockingContract.relock(lockId2, alice, 60, 12, 0);

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

  function test_relock_shouldAccountCorrectly_whenMultipleAccounts_inCliff() public {
    mentoToken.mint(alice, 100);
    mentoToken.mint(bob, 100);
    mentoToken.mint(charlie, 100);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(lockingContract), type(uint256).max);
    vm.prank(charlie);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    vm.prank(alice);
    uint256 lockId1 = lockingContract.lock(alice, alice, 20, 4, 2);

    vm.prank(bob);
    uint256 lockId2 = lockingContract.lock(bob, bob, 30, 3, 3);

    vm.prank(charlie);
    uint256 lockId3 = lockingContract.lock(charlie, charlie, 40, 4, 4);

    _incrementBlock(4 * weekInBlocks);

    vm.prank(bob);
    lockingContract.relock(lockId2, bob, 30, 6, 1);

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

  function test_relock_shouldAccountCorrectly_whenMultipleAccounts_inTail() public {
    mentoToken.mint(alice, 100);
    mentoToken.mint(bob, 100);
    mentoToken.mint(charlie, 100);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(lockingContract), type(uint256).max);
    vm.prank(charlie);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    vm.prank(alice);
    uint256 lockId1 = lockingContract.lock(alice, alice, 20, 4, 2);

    vm.prank(bob);
    uint256 lockId2 = lockingContract.lock(bob, bob, 32, 4, 3);

    vm.prank(charlie);
    uint256 lockId3 = lockingContract.lock(charlie, charlie, 40, 4, 4);

    _incrementBlock(6 * weekInBlocks);

    vm.prank(bob);
    lockingContract.relock(lockId2, bob, 22, 5, 1);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 42);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 78);
    assertEq(mentoToken.balanceOf(charlie), 80);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 32);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 78);
    assertEq(mentoToken.balanceOf(charlie), 90);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    vm.prank(bob);
    lockingContract.withdraw();
    vm.prank(charlie);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 17);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 83);
    assertEq(mentoToken.balanceOf(charlie), 100);

    _incrementBlock(4 * weekInBlocks);

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
