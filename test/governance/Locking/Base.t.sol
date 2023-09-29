// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { TestSetup } from "../TestSetup.sol";
import { TestLocking } from "../../utils/TestLocking.sol";
import { MockMentoToken } from "../../mocks/MockMentoToken.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

contract Locking_Test is TestSetup {
  TestLocking public lockingContract;
  MockMentoToken public mentoToken;

  uint32 public startingPointWeek;
  uint32 public minCliffPeriod;
  uint32 public minSlopePeriod;

  uint32 public weekInBlocks;

  function setUp() public virtual {
    mentoToken = new MockMentoToken();
    lockingContract = new TestLocking();
    vm.prank(owner);

    lockingContract.__Locking_init(
      IERC20Upgradeable(address(mentoToken)),
      startingPointWeek,
      minCliffPeriod,
      minSlopePeriod
    );

    weekInBlocks = uint32(lockingContract.WEEK());

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    _incrementBlock(2 * weekInBlocks + 1);
  }

  function _incrementBlock(uint32 _amount) internal {
    lockingContract.incrementBlock(_amount);
  }

  function test_init_shouldSetState() public {
    assertEq(address(lockingContract.token()), address(mentoToken));

    assertEq(lockingContract.startingPointWeek(), 0);
    assertEq(lockingContract.minCliffPeriod(), 0);
    assertEq(lockingContract.minSlopePeriod(), 0);
    assertEq(lockingContract.owner(), owner);
  }

  function test_stop_shoulRevert_whenNoOwner() public {
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    lockingContract.stop();
  }

  function test_stop_shouldAccountBalancesCorrectly() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(alice, bob, 60, 30, 0);

    vm.prank(owner);
    lockingContract.stop();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 60);
    assertEq(mentoToken.balanceOf(alice), 40);
    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.totalSupply(), 0);
  }

  function test_stop_blocksLockCalls() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(alice, bob, 60, 30, 0);

    vm.prank(owner);
    lockingContract.stop();

    vm.expectRevert("stopped");
    vm.prank(alice);
    lockingContract.lock(alice, bob, 60, 30, 0);
  }

  function test_stop_shouldAllowWithdraws() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(alice, bob, 60, 30, 0);

    vm.prank(owner);
    lockingContract.stop();

    vm.prank(alice);
    lockingContract.withdraw();
  }

  function test_lock_shouldRevert_whenSlopeIsLarge() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("period too big");
    vm.prank(alice);
    lockingContract.lock(alice, alice, 1000, 105, 0);
  }

  function test_lock_shouldRevert_whenCliffeIsLarge() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("cliff too big");
    vm.prank(alice);
    lockingContract.lock(alice, alice, 1000, 11, 105);
  }

  function test_lock_shouldRevert_whenAmountIsZero() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("zero amount");
    vm.prank(alice);
    lockingContract.lock(alice, alice, 0, 10, 10);
  }

  function test_lock_shouldRevert_whenSlopeIsZero() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert();
    vm.prank(alice);
    lockingContract.lock(alice, alice, 10000, 0, 10);
  }

  function test_lock_shouldRevert_whenSlopeBiggerThanAmount() public {
    mentoToken.mint(alice, 1500);

    vm.expectRevert("Wrong value slopePeriod");
    vm.prank(alice);
    lockingContract.lock(alice, alice, 20, 40, 0);
  }

  function test_withdraw_shouldReleaseCorrectAmount_whenInCliff() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(alice, alice, 30, 3, 3);

    _incrementBlock(3 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20);
    assertEq(mentoToken.balanceOf(alice), 80);
  }

  function test_withdraw_shouldNotAffect_whenCalledFromAnotherAccount() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(alice, alice, 30, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(bob);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
  }

  function test_withdraw_shouldNotReleaseTokens_whenTheLockIsDedicatedToSomeoneElse() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(bob, bob, 30, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
  }

  function test_withdraw_shouldReleaseTokens_whenCalledByTheOwnerOfTheLock() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(bob, bob, 30, 3, 0);

    _incrementBlock(weekInBlocks);

    vm.prank(bob);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 20);
    assertEq(mentoToken.balanceOf(alice), 70);
    assertEq(mentoToken.balanceOf(bob), 10);
  }

  function test_withdraw_shouldReleaseCorrectAmounts_whenWithdarMultipleTimes_andWithTail() public {
    mentoToken.mint(alice, 6000);

    vm.prank(alice);
    lockingContract.lock(alice, alice, 5200, 52, 53);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 5200);
    assertEq(mentoToken.balanceOf(alice), 800);
    assertEq(lockingContract.balanceOf(alice), 4220);

    _incrementBlock(103 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(lockingContract.balanceOf(alice), 120);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 100);
    assertEq(mentoToken.balanceOf(alice), 5900);
    assertEq(lockingContract.balanceOf(alice), 38);

    _incrementBlock(weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 6000);
    assertEq(lockingContract.balanceOf(alice), 0);
  }

  function test_withdraw_shouldReleaseCorrectAmounts_whenWithdarMultipleTimes_andNoTail() public {
    mentoToken.mint(alice, 600000); // top up account

    vm.prank(alice);
    lockingContract.lock(alice, alice, 520000, 20, 20);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 520000);
    assertEq(mentoToken.balanceOf(alice), 80000);
    assertEq(lockingContract.balanceOf(alice), 224776);

    _incrementBlock(20 * weekInBlocks);

    vm.prank(alice);
    lockingContract.withdraw();
    assertEq(mentoToken.balanceOf(address(lockingContract)), 520000);
    assertEq(mentoToken.balanceOf(alice), 80000);
    assertEq(lockingContract.balanceOf(alice), 224776);

    _incrementBlock(20 * weekInBlocks);
    vm.prank(alice);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 600000);
    assertEq(lockingContract.balanceOf(alice), 0);
  }

  function test_getLock_shouldReturnCorrectValues() public {
    uint96 amount = 60000;
    uint32 slopePeriod = 30;
    uint32 cliff = 30;
    (uint96 lockAmount, uint96 lockSlope) = lockingContract.getLock(amount, slopePeriod, cliff);
    assertEq(lockAmount, 32903);
    assertEq(lockSlope, 1097);

    amount = 96000;
    slopePeriod = 48;
    cliff = 48;
    (lockAmount, lockSlope) = lockingContract.getLock(amount, slopePeriod, cliff);
    assertEq(lockAmount, 72713);
    assertEq(lockSlope, 1515);

    amount = 104000;
    slopePeriod = 104;
    cliff = 0;
    (lockAmount, lockSlope) = lockingContract.getLock(amount, slopePeriod, cliff);
    assertEq(lockAmount, 62400);
    assertEq(lockSlope, 600);

    amount = 104000;
    slopePeriod = 1;
    cliff = 103;
    (lockAmount, lockSlope) = lockingContract.getLock(amount, slopePeriod, cliff);
    assertEq(lockAmount, 104399);
    assertEq(lockSlope, 104399);
  }

  function test_getWeek_shouldReturnCorrectWeekNo() public {
    uint32 dayInBlocks = weekInBlocks / 7;
    uint32 currentBlock = 21664044; // (Sep-29-2023 11:59:59 AM +UTC) Friday

    lockingContract.setBlock(currentBlock);
    lockingContract.setEpochShift(3564);

    assertEq(lockingContract.getWeek(), 179);
    assertEq(lockingContract.blockTillNextPeriod(), 112320); // 6.5 days in blocks CELO

    _incrementBlock(5 * dayInBlocks);
    assertEq(lockingContract.getWeek(), 179);
    _incrementBlock(dayInBlocks);
    assertEq(lockingContract.getWeek(), 179);
    _incrementBlock(dayInBlocks);
    assertEq(lockingContract.getWeek(), 180);
  }

  function test_getAvailableForWithdraw_shouldReturnCorrectAmount() public {
    mentoToken.mint(alice, 100);

    vm.prank(alice);
    lockingContract.lock(alice, alice, 30, 3, 0);

    _incrementBlock(2 * weekInBlocks);

    vm.prank(alice);
    uint256 availableForWithdraw = lockingContract.getAvailableForWithdraw(alice);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
    assertEq(availableForWithdraw, 20);
  }

  function test_viewFuctions_shouldReturnCorrectValues_whenAfterALockCreated() public {
    uint256 lockId;
    uint256 lockBlock;
    uint256 voteBlock;
    uint256 delegateBlock;
    uint256 relockBlock;

    _incrementBlock(weekInBlocks + 1);
    mentoToken.mint(alice, 1000000);

    _incrementBlock(weekInBlocks / 2);

    lockBlock = lockingContract.blockNumberMocked();

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 3000, 3, 0);
    // WEEK 1
    assertEq(mentoToken.balanceOf(address(lockingContract)), 3000);
    assertEq(lockingContract.balanceOf(alice), 634);
    assertEq(lockingContract.getVotes(alice), 634);

    // WEEK 2
    _incrementBlock(weekInBlocks / 2 + weekInBlocks / 4);

    delegateBlock = lockingContract.blockNumberMocked();
    voteBlock = delegateBlock + weekInBlocks / 4;

    assertEq(lockingContract.balanceOf(alice), 422);
    assertEq(lockingContract.getVotes(alice), 422);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, bob);

    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 422);
    assertEq(lockingContract.getVotes(bob), 422);

    assertEq(lockingContract.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(lockingContract.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(lockingContract.getPastTotalSupply(delegateBlock - 1), 422);

    _incrementBlock(weekInBlocks / 2);

    relockBlock = lockingContract.blockNumberMocked();

    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 422);
    assertEq(lockingContract.getVotes(bob), 422);

    assertEq(lockingContract.getPastVotes(alice, voteBlock), 0);
    assertEq(lockingContract.getPastVotes(bob, voteBlock), 422);
    assertEq(lockingContract.getPastTotalSupply(voteBlock), 422);

    assertEq(lockingContract.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(lockingContract.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(lockingContract.getPastTotalSupply(delegateBlock - 1), 422);

    vm.prank(alice);
    lockingContract.relock(lockId, charlie, 4000, 4, 0);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 4000);
    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.getVotes(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 861);
    assertEq(lockingContract.getVotes(charlie), 861);

    assertEq(lockingContract.getPastVotes(alice, voteBlock), 0);
    assertEq(lockingContract.getPastVotes(bob, voteBlock), 422);
    assertEq(lockingContract.getPastTotalSupply(voteBlock), 422);

    assertEq(lockingContract.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(lockingContract.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(lockingContract.getPastTotalSupply(delegateBlock - 1), 422);

    assertEq(lockingContract.getPastVotes(alice, relockBlock - 1), 0);
    assertEq(lockingContract.getPastVotes(bob, relockBlock - 1), 422);
    assertEq(lockingContract.getPastTotalSupply(relockBlock - 1), 422);

    // WEEK 3

    _incrementBlock(weekInBlocks / 4);
    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.getVotes(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 645);
    assertEq(lockingContract.getVotes(charlie), 645);

    uint256 currentBlock = lockingContract.blockNumberMocked();

    vm.expectRevert("block not yet mined");
    lockingContract.getPastVotes(alice, currentBlock);

    vm.expectRevert("block not yet mined");
    lockingContract.getPastTotalSupply(currentBlock);
  }
}
