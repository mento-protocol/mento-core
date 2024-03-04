// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";
import { MockLocking } from "../../mocks/MockLocking.sol";

contract Lock_Locking_Test is Locking_Test {
  function test_init_shouldSetState() public {
    assertEq(address(locking.token()), address(mentoToken));

    assertEq(locking.startingPointWeek(), 0);
    assertEq(locking.minCliffPeriod(), 0);
    assertEq(locking.minSlopePeriod(), 0);
    assertEq(locking.owner(), owner);
  }

  function test_stop_shoulRevert_whenNoOwner() public {
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    locking.stop();
  }

  function test_stop_shouldAccountBalancesCorrectly() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, alice, 60, 30, 0);

    vm.prank(owner);
    locking.stop();

    assertEq(mentoToken.balanceOf(address(locking)), 60);
    assertEq(mentoToken.balanceOf(alice), 40);
    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.totalSupply(), 0);
  }

  function test_stop_shouldBlockNewLocks() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, bob, 60, 30, 0);

    vm.prank(owner);
    locking.stop();

    vm.expectRevert("stopped");
    vm.prank(alice);
    locking.lock(alice, bob, 60, 30, 0);
  }

  function test_stop_shouldAllowWithdraws() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, alice, 60, 30, 0);

    vm.prank(owner);
    locking.stop();

    vm.prank(alice);
    locking.withdraw();
  }

  function test_lock_whenSlopeIsLarge_shouldRevert() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("period too big");
    vm.prank(alice);
    locking.lock(alice, alice, 1000, 105, 0);
  }

  function test_lock_whenCliffeIsLarge_shouldRevert() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("cliff too big");
    vm.prank(alice);
    locking.lock(alice, alice, 1000, 11, 105);
  }

  function test_lock_whenAmountIsZero_shouldRevert() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("zero amount");
    vm.prank(alice);
    locking.lock(alice, alice, 0, 10, 10);
  }

  function test_lock_whenSlopeIsZero_shouldRevert() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert();
    vm.prank(alice);
    locking.lock(alice, alice, 10000, 0, 10);
  }

  function test_lock_whenSlopeBiggerThanAmount_shouldRevert() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("Wrong value slopePeriod");
    vm.prank(alice);
    locking.lock(alice, alice, 20, 40, 0);
  }

  function test_withdraw_whenInSlope_shouldReleaseCorrectAmount() public {
    mentoToken.mint(alice, 1000);

    vm.prank(alice);
    locking.lock(alice, alice, 300, 3, 3);

    _incrementBlock(3 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 300);
    assertEq(mentoToken.balanceOf(alice), 700);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 200);
    assertEq(mentoToken.balanceOf(alice), 800);
  }

  function test_withdraw_whenCalledFromAnotherAccount_shouldNotSendTokens() public {
    mentoToken.mint(alice, 1000);

    vm.prank(alice);
    locking.lock(alice, alice, 300, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(bob);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 300);
    assertEq(mentoToken.balanceOf(alice), 700);
  }

  function test_withdraw_whenTheLockIsCreatedForSomeoneElse_shouldNotReleaseTokens() public {
    mentoToken.mint(alice, 1000);

    vm.prank(alice);
    locking.lock(bob, bob, 300, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 300);
    assertEq(mentoToken.balanceOf(alice), 700);
  }

  function test_withdraw_whenCalledByTheOwnerOfTheLock_shouldReleaseTokens() public {
    mentoToken.mint(alice, 1000);

    vm.prank(alice);
    locking.lock(bob, bob, 300, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(bob);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 200);
    assertEq(mentoToken.balanceOf(alice), 700);
    assertEq(mentoToken.balanceOf(bob), 100);
  }

  function test_withdraw_whenTailInVeToken_shouldReleaseCorrectAmounts() public {
    mentoToken.mint(alice, 6000);

    vm.prank(alice);
    locking.lock(alice, alice, 5200, 52, 53);

    assertEq(mentoToken.balanceOf(address(locking)), 5200);
    assertEq(mentoToken.balanceOf(alice), 800);
    // (52 / 104 + 53 / 103) * 5200 = 5275 > 5200
    assertEq(locking.balanceOf(alice), 5200);

    _incrementBlock(103 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(locking.balanceOf(alice), 200);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 100);
    assertEq(mentoToken.balanceOf(alice), 5900);
    assertEq(locking.balanceOf(alice), 100);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(alice), 6000);
    assertEq(locking.balanceOf(alice), 0);
  }

  function test_getLock_shouldReturnCorrectValues() public {
    uint96 amount = 60000;
    uint32 slopePeriod = 30;
    uint32 cliff = 30;
    (uint96 lockAmount, uint96 lockSlope) = locking.getLock(amount, slopePeriod, cliff);
    // floor ((30 / 104 + 30 / 103) * 60000) = 34783
    assertEq(lockAmount, 34783);
    // divUp (34783, 30) = 1160
    assertEq(lockSlope, 1160);

    amount = 96000;
    slopePeriod = 48;
    cliff = 48;
    (lockAmount, lockSlope) = locking.getLock(amount, slopePeriod, cliff);
    // floor ((48 / 104 + 48 / 103) * 96000) = 89045
    assertEq(lockAmount, 89045);
    // divUp (89045, 48)  = 1856
    assertEq(lockSlope, 1856);

    amount = 104000;
    slopePeriod = 104;
    cliff = 0;
    (lockAmount, lockSlope) = locking.getLock(amount, slopePeriod, cliff);
    // floor ((104 / 104 + 0 / 103) * 104000) = 104000
    assertEq(lockAmount, 104000);
    // divUp (104000, 104) = 1000
    assertEq(lockSlope, 1000);

    amount = 104000;
    slopePeriod = 24;
    cliff = 103;
    (lockAmount, lockSlope) = locking.getLock(amount, slopePeriod, cliff);
    // floor ((24 / 104 + 103 / 103) * 104000) = 128000 > 104000
    assertEq(lockAmount, 104000);
    // divUp (104000, 24) = 4334
    assertEq(lockSlope, 4334);
  }

  function test_getWeek_shouldReturnCorrectWeekNo() public {
    uint32 dayInBlocks = weekInBlocks / 7;
    uint32 currentBlock = 21664044; // (Sep-29-2023 11:59:59 AM +UTC) Friday
    locking.setBlock(currentBlock);

    // without shifting, it is week #179 with 12_204 blocks reminder
    assertEq(locking.getWeek(), 179);

    locking.setEpochShift(89_964);

    // since we shift more than remainder(89_964 > 12_204), we are now in the previous week, #178
    assertEq(locking.getWeek(), 178);

    // FRI 12:00 -> WED 00:00 = 4.5 days
    assertEq(locking.blockTillNextPeriod(), (9 * dayInBlocks) / 2);

    _incrementBlock(3 * dayInBlocks);
    assertEq(locking.getWeek(), 178);
    _incrementBlock(dayInBlocks);
    assertEq(locking.getWeek(), 178);
    _incrementBlock(dayInBlocks);
    assertEq(locking.getWeek(), 179);
  }

  function test_getAvailableForWithdraw_shouldReturnCorrectAmount() public {
    mentoToken.mint(alice, 1000);

    vm.prank(alice);
    locking.lock(alice, alice, 300, 3, 0);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    uint256 availableForWithdraw = locking.getAvailableForWithdraw(alice);

    assertEq(mentoToken.balanceOf(address(locking)), 300);
    assertEq(mentoToken.balanceOf(alice), 700);
    assertEq(availableForWithdraw, 200);
  }

  function test_viewFuctions_shouldReturnCorrectValues() public {
    uint256 lockId;
    uint256 lockBlock;
    uint256 voteBlock;
    uint256 delegateBlock;
    uint256 relockBlock;

    _incrementBlock(weekInBlocks + 1);
    mentoToken.mint(alice, 1000000);

    _incrementBlock(weekInBlocks / 2);

    lockBlock = locking.blockNumberMocked();

    vm.prank(alice);
    lockId = locking.lock(alice, alice, 3000, 3, 0);
    // WEEK 1
    assertEq(mentoToken.balanceOf(address(locking)), 3000);
    // 3 / 104 * 3000 = 86
    assertEq(locking.balanceOf(alice), 86);
    assertEq(locking.getVotes(alice), 86);

    // WEEK 2
    _incrementBlock(weekInBlocks / 2 + weekInBlocks / 4);

    delegateBlock = locking.blockNumberMocked();
    voteBlock = delegateBlock + weekInBlocks / 4;
    // 86 * 2 / 3 = 57
    assertEq(locking.balanceOf(alice), 57);
    assertEq(locking.getVotes(alice), 57);

    vm.prank(alice);
    locking.delegateTo(lockId, bob);

    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 57);
    assertEq(locking.getVotes(bob), 57);

    assertEq(locking.getPastVotes(alice, delegateBlock - 1), 57);
    assertEq(locking.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(locking.getPastTotalSupply(delegateBlock - 1), 57);

    _incrementBlock(weekInBlocks / 2);

    relockBlock = locking.blockNumberMocked();

    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 57);
    assertEq(locking.getVotes(bob), 57);

    assertEq(locking.getPastVotes(alice, voteBlock), 0);
    assertEq(locking.getPastVotes(bob, voteBlock), 57);
    assertEq(locking.getPastTotalSupply(voteBlock), 57);

    assertEq(locking.getPastVotes(alice, delegateBlock - 1), 57);
    assertEq(locking.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(locking.getPastTotalSupply(delegateBlock - 1), 57);

    vm.prank(alice);
    locking.relock(lockId, charlie, 4000, 4, 0);

    assertEq(mentoToken.balanceOf(address(locking)), 4000);
    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.getVotes(bob), 0);
    // 4 / 104 * 4000 = 153
    assertEq(locking.balanceOf(charlie), 153);
    assertEq(locking.getVotes(charlie), 153);

    assertEq(locking.getPastVotes(alice, voteBlock), 0);
    assertEq(locking.getPastVotes(bob, voteBlock), 57);
    assertEq(locking.getPastTotalSupply(voteBlock), 57);

    assertEq(locking.getPastVotes(alice, delegateBlock - 1), 57);
    assertEq(locking.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(locking.getPastTotalSupply(delegateBlock - 1), 57);

    assertEq(locking.getPastVotes(alice, relockBlock - 1), 0);
    assertEq(locking.getPastVotes(bob, relockBlock - 1), 57);
    assertEq(locking.getPastTotalSupply(relockBlock - 1), 57);

    // WEEK 3

    _incrementBlock(weekInBlocks / 4);
    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.getVotes(bob), 0);
    // 153 * 3 / 4 = 114
    assertEq(locking.balanceOf(charlie), 114);
    assertEq(locking.getVotes(charlie), 114);

    uint256 currentBlock = locking.blockNumberMocked();

    vm.expectRevert("block not yet mined");
    locking.getPastVotes(alice, currentBlock);

    vm.expectRevert("block not yet mined");
    locking.getPastTotalSupply(currentBlock);
  }
}
