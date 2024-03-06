// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract Relock_Locking_Test is Locking_Test {
  uint256 public lockId;

  function test_relock_whenDelegateZero_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("delegate is zero");
    vm.prank(alice);
    locking.relock(lockId, address(0), 30, 3, 3);
  }

  function test_relock_whenInCliff_shouldRelockWithIncreasedAmount() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.relock(lockId, alice, 45, 9, 0);

    assertEq(mentoToken.balanceOf(address(locking)), 45);
    assertEq(mentoToken.balanceOf(alice), 55);

    _incrementBlock(9 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_whenInCliff_shouldRelockWithNewCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.relock(lockId, alice, 30, 3, 4);

    assertEq(mentoToken.balanceOf(address(locking)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);

    _incrementBlock(7 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_whenInCliff_sholdRelockWithNewSlope() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.relock(lockId, alice, 35, 18, 0);

    assertEq(mentoToken.balanceOf(address(locking)), 35);
    assertEq(mentoToken.balanceOf(alice), 65);

    _incrementBlock(18 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_whenInCliff_shouldRelockWithANewSchedle() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 30, 3, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.relock(lockId, alice, 80, 16, 6);

    assertEq(mentoToken.balanceOf(address(locking)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(6 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(16 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_wheInSlope_shouldRelockWithNewSchedule() public {
    mentoToken.mint(alice, 1000);

    vm.startPrank(alice);
    lockId = locking.lock(alice, alice, 300, 3, 0);
    _incrementBlock(2 * weekInBlocks);

    locking.relock(lockId, alice, 800, 16, 6);

    assertEq(mentoToken.balanceOf(address(locking)), 800);
    assertEq(mentoToken.balanceOf(alice), 200);

    _incrementBlock(6 * weekInBlocks);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 800);
    assertEq(mentoToken.balanceOf(alice), 200);

    _incrementBlock(16 * weekInBlocks);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000);

    vm.stopPrank();
  }

  function test_relock_whenRelocked_shouldReleaseByTheNewScheduleAfterWithdraw() public {
    mentoToken.mint(alice, 1000);

    vm.startPrank(alice);
    lockId = locking.lock(alice, alice, 300, 3, 0);
    _incrementBlock(2 * weekInBlocks);

    locking.relock(lockId, alice, 800, 16, 6);

    assertEq(mentoToken.balanceOf(address(locking)), 800);
    assertEq(mentoToken.balanceOf(alice), 200);

    _incrementBlock(6 * weekInBlocks);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 800);
    assertEq(mentoToken.balanceOf(alice), 200);

    _incrementBlock(16 * weekInBlocks);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000);

    vm.stopPrank();
  }

  function test_relock_whenInTail_shouldRelockWithNewSchedule() public {
    mentoToken.mint(alice, 1000);

    vm.startPrank(alice);
    lockId = locking.lock(alice, alice, 370, 4, 3);

    _incrementBlock(6 * weekInBlocks);

    locking.relock(lockId, alice, 100, 2, 2);

    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 100);
    assertEq(mentoToken.balanceOf(alice), 900);

    _incrementBlock(2 * weekInBlocks);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 100);
    assertEq(mentoToken.balanceOf(alice), 900);

    _incrementBlock(2 * weekInBlocks);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000);

    vm.stopPrank();
  }

  function test_relock_whenAmountLessThanCurrent_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 38, 4, 3);
    _incrementBlock(6 * weekInBlocks);

    vm.expectRevert("Impossible to relock: less amount, then now is");
    vm.prank(alice);
    locking.relock(lockId, alice, 5, 1, 1);
  }

  function test_relock_whenPeriodTooShort_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("new line period lock too short");
    vm.prank(alice);
    locking.relock(lockId, alice, 5, 1, 1);
  }

  function test_relock_whenAmountIsZero_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("zero amount");
    vm.prank(alice);
    locking.relock(lockId, alice, 0, 5, 1);
  }

  function test_relock_whenSlopeIsZero_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("slope period equal 0");
    vm.prank(alice);
    locking.relock(lockId, alice, 60, 0, 2);
  }

  function test_relock_whenCliffIsBig_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("cliff too big");
    vm.prank(alice);
    locking.relock(lockId, alice, 60, 12, 105);
  }

  function test_relock_whenSlopeIsBig_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 38, 4, 3);
    _incrementBlock(2 * weekInBlocks);

    vm.expectRevert("slope period too big");
    vm.prank(alice);
    locking.relock(lockId, alice, 60, 210, 10);
  }

  function test_delegate_withoutRelock() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 60000, 30, 0);
    // 60000 * 30 / 104 = 17307
    assertEq(locking.balanceOf(bob), 17307);
    assertEq(mentoToken.balanceOf(address(locking)), 60000);
    assertEq(mentoToken.balanceOf(alice), 40000);

    _incrementBlock(29 * weekInBlocks);
    // (17307 - 1) / 30 + 1 = 577
    // 17307 - 29 * 577 = 574
    assertEq(locking.balanceOf(bob), 574);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 2000);
    assertEq(mentoToken.balanceOf(alice), 98000);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(locking.balanceOf(bob), 0);
    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_relock_shouldAccountDelegatedAmountCorrectly() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 60000, 30, 0);

    // 60000 * 30 / 104 = 17307
    assertEq(locking.balanceOf(bob), 17307);

    _incrementBlock(20 * weekInBlocks);
    // (17307 - 1) / 30 + 1 = 577
    // 17307 - 20 * 577 = 5767
    assertEq(locking.balanceOf(bob), 5767);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 20000);
    assertEq(mentoToken.balanceOf(alice), 80000);

    vm.prank(alice);
    locking.relock(lockId, charlie, 20000, 10, 0);

    assertEq(locking.balanceOf(bob), 0);
    // 20000 * 10 / 104 = 1923
    assertEq(locking.balanceOf(charlie), 1923);

    _incrementBlock(10 * weekInBlocks);

    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.balanceOf(charlie), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100000);
  }

  function test_relock_whenUnknownLock_shouldRevert() public {
    mentoToken.mint(alice, 100000);

    vm.prank(alice);
    lockId = locking.lock(alice, bob, 60000, 30, 0);

    _incrementBlock(20 * weekInBlocks);
    // 60000 * 30 / 104 = 17307
    // (17307 - 1) / 30 + 1 = 577
    // 17307 - 20 * 577 = 5767
    assertEq(locking.balanceOf(bob), 5767);

    vm.prank(alice);
    locking.withdraw();

    lockId = 1337; // does not exist

    vm.expectRevert("caller not a lock owner");
    vm.prank(alice);
    locking.relock(lockId, charlie, 20000, 10, 0);
  }

  function test_relock_whenMultiLinesInCliff_shouldRelockCorrectLine() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, alice, 30, 3, 3);

    vm.prank(alice);
    uint256 lockId2 = locking.lock(alice, alice, 50, 5, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.relock(lockId2, alice, 60, 6, 0);

    assertEq(mentoToken.balanceOf(address(locking)), 90);
    assertEq(mentoToken.balanceOf(alice), 10);

    _incrementBlock(weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(5 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_whenMultiLinesInCliff_shouldRelockCorrectLine2() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    uint256 lockId1 = locking.lock(alice, alice, 30, 3, 3);

    vm.prank(alice);
    locking.lock(alice, alice, 50, 5, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.relock(lockId1, alice, 50, 10, 0);

    assertEq(mentoToken.balanceOf(address(locking)), 100);
    assertEq(mentoToken.balanceOf(alice), 0);

    _incrementBlock(weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 95);
    assertEq(mentoToken.balanceOf(alice), 5);

    _incrementBlock(9 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
  }

  function test_relock_whenMultiLinesCutCorner_shouldRevert() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, alice, 30, 3, 3);

    vm.prank(alice);
    uint256 lockId2 = locking.lock(alice, alice, 50, 5, 3);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    vm.expectRevert("detect cut deposit corner");
    locking.relock(lockId2, alice, 50, 10, 0);
  }

  function test_relock_whenMultiLinesInSlope_shouldRelockCorrectly() public {
    mentoToken.mint(alice, 1000);

    vm.prank(alice);
    locking.lock(alice, alice, 300, 3, 0);

    vm.prank(alice);
    uint256 lockId2 = locking.lock(alice, alice, 300, 3, 0);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.relock(lockId2, alice, 600, 12, 0);

    assertEq(mentoToken.balanceOf(address(locking)), 700);
    assertEq(mentoToken.balanceOf(alice), 300);

    _incrementBlock(weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 550);
    assertEq(mentoToken.balanceOf(alice), 450);

    _incrementBlock(11 * weekInBlocks);
    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 1000);
  }

  function test_relock_whenMultiAccountsInCliff_shouldRelockCorrectly() public {
    mentoToken.mint(alice, 100);
    mentoToken.mint(bob, 100);
    mentoToken.mint(charlie, 100);

    vm.prank(alice);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(charlie);
    mentoToken.approve(address(locking), type(uint256).max);

    vm.prank(alice);
    locking.lock(alice, alice, 20, 4, 2);

    vm.prank(bob);
    uint256 lockId2 = locking.lock(bob, bob, 30, 3, 3);

    vm.prank(charlie);
    locking.lock(charlie, charlie, 40, 4, 4);

    _incrementBlock(4 * weekInBlocks);

    vm.prank(bob);
    locking.relock(lockId2, bob, 30, 6, 1);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 80);
    assertEq(mentoToken.balanceOf(alice), 90);
    assertEq(mentoToken.balanceOf(bob), 70);
    assertEq(mentoToken.balanceOf(charlie), 60);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 65);
    assertEq(mentoToken.balanceOf(alice), 95);
    assertEq(mentoToken.balanceOf(bob), 70);
    assertEq(mentoToken.balanceOf(charlie), 70);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 45);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 75);
    assertEq(mentoToken.balanceOf(charlie), 80);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 15);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 85);
    assertEq(mentoToken.balanceOf(charlie), 100);

    _incrementBlock(3 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 100);
    assertEq(mentoToken.balanceOf(charlie), 100);
  }

  function test_relock_whenMultiAccountsInTail_shouldRelockCorrectly() public {
    mentoToken.mint(alice, 100);
    mentoToken.mint(bob, 100);
    mentoToken.mint(charlie, 100);

    vm.prank(alice);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(charlie);
    mentoToken.approve(address(locking), type(uint256).max);

    vm.prank(alice);
    locking.lock(alice, alice, 20, 4, 2);

    vm.prank(bob);
    uint256 lockId2 = locking.lock(bob, bob, 32, 4, 3);

    vm.prank(charlie);
    locking.lock(charlie, charlie, 40, 4, 4);

    _incrementBlock(6 * weekInBlocks);

    vm.prank(bob);
    locking.relock(lockId2, bob, 22, 5, 1);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 42);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 78);
    assertEq(mentoToken.balanceOf(charlie), 80);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 32);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 78);
    assertEq(mentoToken.balanceOf(charlie), 90);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 17);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 83);
    assertEq(mentoToken.balanceOf(charlie), 100);

    _incrementBlock(4 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();
    vm.prank(bob);
    locking.withdraw();
    vm.prank(charlie);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);
    assertEq(mentoToken.balanceOf(bob), 100);
    assertEq(mentoToken.balanceOf(charlie), 100);
  }
}
