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
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, alice, 30, 3, 3);

    _incrementBlock(3 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 20);
    assertEq(mentoToken.balanceOf(alice), 80);
  }

  function test_withdraw_whenCalledFromAnotherAccount_shouldNotSendTokens() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, alice, 30, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(bob);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
  }

  function test_withdraw_whenTheLockIsCreatedForSomeoneElse_shouldNotReleaseTokens() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(bob, bob, 30, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
  }

  function test_withdraw_whenCalledByTheOwnerOfTheLock_shouldReleaseTokens() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(bob, bob, 30, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(bob);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 20);
    assertEq(mentoToken.balanceOf(alice), 70);
    assertEq(mentoToken.balanceOf(bob), 10);
  }

  function test_withdraw_whenTailInVeToken_shouldReleaseCorrectAmounts() public {
    mentoToken.mint(alice, 6000);

    vm.prank(alice);
    locking.lock(alice, alice, 5200, 52, 53);

    assertEq(mentoToken.balanceOf(address(locking)), 5200);
    assertEq(mentoToken.balanceOf(alice), 800);
    assertEq(locking.balanceOf(alice), 4220);

    _incrementBlock(103 * weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(locking.balanceOf(alice), 120);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 100);
    assertEq(mentoToken.balanceOf(alice), 5900);
    assertEq(locking.balanceOf(alice), 38);

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
    assertEq(lockAmount, 32903);
    assertEq(lockSlope, 1097);

    amount = 96000;
    slopePeriod = 48;
    cliff = 48;
    (lockAmount, lockSlope) = locking.getLock(amount, slopePeriod, cliff);
    assertEq(lockAmount, 72713);
    assertEq(lockSlope, 1515);

    amount = 104000;
    slopePeriod = 104;
    cliff = 0;
    (lockAmount, lockSlope) = locking.getLock(amount, slopePeriod, cliff);
    assertEq(lockAmount, 62400);
    assertEq(lockSlope, 600);

    amount = 104000;
    slopePeriod = 1;
    cliff = 103;
    (lockAmount, lockSlope) = locking.getLock(amount, slopePeriod, cliff);
    assertEq(lockAmount, 104399);
    assertEq(lockSlope, 104399);
  }

  function test_getWeek_shouldReturnCorrectWeekNo() public {
    uint32 dayInBlocks = weekInBlocks / 7;
    uint32 currentBlock = 21664044; // (Sep-29-2023 11:59:59 AM +UTC) Friday

    locking.setBlock(currentBlock);
    locking.setEpochShift(3564);

    assertEq(locking.getWeek(), 179);
    assertEq(locking.blockTillNextPeriod(), 112320); // 6.5 days in blocks CELO

    _incrementBlock(5 * dayInBlocks);
    assertEq(locking.getWeek(), 179);
    _incrementBlock(dayInBlocks);
    assertEq(locking.getWeek(), 179);
    _incrementBlock(dayInBlocks);
    assertEq(locking.getWeek(), 180);
  }

  function test_getAvailableForWithdraw_shouldReturnCorrectAmount() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    locking.lock(alice, alice, 30, 3, 0);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    uint256 availableForWithdraw = locking.getAvailableForWithdraw(alice);

    assertEq(mentoToken.balanceOf(address(locking)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
    assertEq(availableForWithdraw, 20);
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
    assertEq(locking.balanceOf(alice), 634);
    assertEq(locking.getVotes(alice), 634);

    // WEEK 2
    _incrementBlock(weekInBlocks / 2 + weekInBlocks / 4);

    delegateBlock = locking.blockNumberMocked();
    voteBlock = delegateBlock + weekInBlocks / 4;

    assertEq(locking.balanceOf(alice), 422);
    assertEq(locking.getVotes(alice), 422);

    vm.prank(alice);
    locking.delegateTo(lockId, bob);

    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 422);
    assertEq(locking.getVotes(bob), 422);

    assertEq(locking.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(locking.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(locking.getPastTotalSupply(delegateBlock - 1), 422);

    _incrementBlock(weekInBlocks / 2);

    relockBlock = locking.blockNumberMocked();

    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 422);
    assertEq(locking.getVotes(bob), 422);

    assertEq(locking.getPastVotes(alice, voteBlock), 0);
    assertEq(locking.getPastVotes(bob, voteBlock), 422);
    assertEq(locking.getPastTotalSupply(voteBlock), 422);

    assertEq(locking.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(locking.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(locking.getPastTotalSupply(delegateBlock - 1), 422);

    vm.prank(alice);
    locking.relock(lockId, charlie, 4000, 4, 0);

    assertEq(mentoToken.balanceOf(address(locking)), 4000);
    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.getVotes(bob), 0);
    assertEq(locking.balanceOf(charlie), 861);
    assertEq(locking.getVotes(charlie), 861);

    assertEq(locking.getPastVotes(alice, voteBlock), 0);
    assertEq(locking.getPastVotes(bob, voteBlock), 422);
    assertEq(locking.getPastTotalSupply(voteBlock), 422);

    assertEq(locking.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(locking.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(locking.getPastTotalSupply(delegateBlock - 1), 422);

    assertEq(locking.getPastVotes(alice, relockBlock - 1), 0);
    assertEq(locking.getPastVotes(bob, relockBlock - 1), 422);
    assertEq(locking.getPastTotalSupply(relockBlock - 1), 422);

    // WEEK 3

    _incrementBlock(weekInBlocks / 4);
    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.getVotes(alice), 0);
    assertEq(locking.balanceOf(bob), 0);
    assertEq(locking.getVotes(bob), 0);
    assertEq(locking.balanceOf(charlie), 645);
    assertEq(locking.getVotes(charlie), 645);

    uint256 currentBlock = locking.blockNumberMocked();

    vm.expectRevert("block not yet mined");
    locking.getPastVotes(alice, currentBlock);

    vm.expectRevert("block not yet mined");
    locking.getPastTotalSupply(currentBlock);
  }

  function test_migrate_shouldMigrateLocks() public {
    MockLocking mockLockingContract = new MockLocking();

    mentoToken.mint(alice, 100000);
    vm.prank(alice);
    uint256 lockId = locking.lock(alice, alice, 60000, 30, 0);

    uint256[] memory ids = new uint256[](1);
    ids[0] = lockId;

    vm.prank(owner);
    locking.startMigration(address(mockLockingContract));

    assertEq(locking.balanceOf(alice), 18923);
    assertEq(locking.totalSupply(), 18923);

    vm.prank(alice);
    locking.migrate(ids);

    assertEq(locking.balanceOf(alice), 0);
    assertEq(locking.totalSupply(), 0);

    assertEq(mentoToken.balanceOf(address(mockLockingContract)), 60000);
    assertEq(locking.totalSupply(), 0);
  }

  function test_migrate_whenDelegatedAndInSlope_shouldMigrateLocks() public {
    MockLocking newLockingContract = new MockLocking();

    mentoToken.mint(alice, 100000);
    vm.prank(alice);
    uint256 lockId = locking.lock(alice, bob, 60000, 30, 0);

    uint256[] memory ids = new uint256[](1);
    ids[0] = lockId;

    _incrementBlock(10 * weekInBlocks);

    vm.prank(owner);
    locking.startMigration(address(newLockingContract));

    vm.prank(alice);
    locking.migrate(ids);

    assertEq(locking.balanceOf(bob), 0);
    assertEq(mentoToken.balanceOf(address(locking)), 20000);
    assertEq(mentoToken.balanceOf(address(newLockingContract)), 40000);
    assertEq(mentoToken.balanceOf(alice), 40000);

    assertEq(locking.totalSupply(), 0);

    vm.prank(alice);
    locking.withdraw();

    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(locking.totalSupply(), 0);
  }

  function test_migrate_whenDelegatedAndInTail_shouldMigrateLocks() public {
    MockLocking newLockingContract = new MockLocking();

    mentoToken.mint(alice, 100);
    vm.prank(alice);
    uint256 lockId = locking.lock(alice, bob, 65, 11, 0);

    uint256[] memory ids = new uint256[](1);
    ids[0] = lockId;

    _incrementBlock(10 * weekInBlocks);

    vm.prank(owner);
    locking.startMigration(address(newLockingContract));

    vm.prank(alice);
    locking.migrate(ids);

    assertEq(mentoToken.balanceOf(address(locking)), 60);
    assertEq(mentoToken.balanceOf(address(newLockingContract)), 5);
    assertEq(mentoToken.balanceOf(alice), 35);

    vm.prank(alice);
    locking.withdraw();
    assertEq(mentoToken.balanceOf(address(locking)), 0);
    assertEq(mentoToken.balanceOf(address(newLockingContract)), 5);
    assertEq(mentoToken.balanceOf(alice), 95);
  }

  function test_startMigration_whenNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    locking.startMigration(address(1));
  }
}
