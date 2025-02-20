// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { LockingTest } from "./LockingTest.sol";

contract Upgrade_LockingTest is LockingTest {
  address public mentoLabs = makeAddr("MentoLabsMultisig");

  uint32 public l1Day;
  uint32 public l2Day;
  uint32 public l1Week;
  uint32 public l2Week;

  function setUp() public override {
    super.setUp();
    l1Week = 7 days / 5;
    l2Week = 7 days;
    l1Day = l1Week / 7;
    l2Day = l2Week / 7;
  }

  function test_initialSetup_shouldHaveCorrectValues() public view {
    assertEq(locking.L2_WEEK(), l2Week);
    assertEq(locking.mentoLabsMultisig(), address(0));
    assertEq(locking.l2TransitionBlock(), 0);
    assertEq(locking.l2StartingPointWeek(), 0);
    assertEq(locking.l2EpochShift(), 0);
    assert(!locking.paused());
  }

  function test_setMentoLabsMultisig_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    locking.setMentoLabsMultisig(mentoLabs);
  }

  function test_setMentoLabsMultisig_whenCalledByOwner_shouldSetMultisigAddress() public {
    vm.prank(owner);
    locking.setMentoLabsMultisig(mentoLabs);

    assertEq(locking.mentoLabsMultisig(), mentoLabs);
  }

  modifier setMultisig() {
    vm.prank(owner);
    locking.setMentoLabsMultisig(mentoLabs);
    _;
  }

  function test_setL2TransitionBlock_whenCalledByNonMentoMultisig_shouldRevert() public setMultisig {
    vm.prank(alice);
    vm.expectRevert("caller is not MentoLabs multisig");
    locking.setL2TransitionBlock(block.number);
  }

  function test_setL2TransitionBlock_whenCalledByMentoMultisig_shouldSetL2BlockAndPause() public setMultisig {
    uint32 blockNumber = uint32(block.number + 100);

    vm.prank(mentoLabs);
    locking.setL2TransitionBlock(blockNumber);

    assertEq(locking.l2TransitionBlock(), blockNumber);
    assert(locking.paused());
  }

  function test_setL2EpochShift_whenCalledByNonMentoMultisig_shouldRevert() public setMultisig {
    vm.prank(alice);
    vm.expectRevert("caller is not MentoLabs multisig");
    locking.setL2EpochShift(100);
  }

  function test_setL2EpochShift_whenCalledByMentoMultisig_shouldSetL2BlockAndPause() public setMultisig {
    vm.prank(mentoLabs);
    locking.setL2EpochShift(100);

    assertEq(locking.l2EpochShift(), 100);
  }

  function test_setL2StartingPointWeek_whenCalledByNonMentoMultisig_shouldRevert() public setMultisig {
    vm.prank(alice);
    vm.expectRevert("caller is not MentoLabs multisig");
    locking.setL2StartingPointWeek(100);
  }

  function test_setL2StartingPointWeek_whenCalledByMentoMultisig_shouldSetL2BlockAndPause() public setMultisig {
    vm.prank(mentoLabs);
    locking.setL2StartingPointWeek(100);

    assertEq(locking.l2StartingPointWeek(), 100);
  }
  function test_setPaused_whenCalledByNonMentoMultisig_shouldRevert() public setMultisig {
    vm.prank(alice);
    vm.expectRevert("caller is not MentoLabs multisig");
    locking.setPaused(true);
  }

  function test_setPaused_whenCalledByMentoMultisig_shouldPauseContracts() public setMultisig {
    mentoToken.mint(alice, 1000000e18);

    vm.prank(mentoLabs);
    locking.setPaused(true);

    assert(locking.paused());

    vm.expectRevert("locking is paused");
    vm.prank(alice);
    locking.lock(alice, bob, 1000e18, 5, 5);

    vm.expectRevert("locking is paused");
    vm.prank(alice);
    locking.withdraw();

    vm.prank(mentoLabs);
    locking.setPaused(false);

    assert(!locking.paused());

    vm.prank(alice);
    locking.lock(alice, bob, 1000e18, 5, 5);

    vm.prank(alice);
    locking.withdraw();
  }

  modifier l2LockingSetup(uint32 advanceWeeks, uint32 startingPointWeek, uint32 l1Shift) {
    vm.prank(owner);
    locking.setMentoLabsMultisig(mentoLabs);

    _incrementBlock(l1Week * advanceWeeks);

    locking.setStatingPointWeek(startingPointWeek);
    locking.setEpochShift(l1Shift);

    vm.prank(mentoLabs);
    locking.setL2TransitionBlock(block.number);

    vm.prank(mentoLabs);
    locking.setPaused(false);

    _;
  }

  function test_getWeek_whenShiftAndStartingPointIs0_shouldReturnCorrectWeekNo() public l2LockingSetup(8, 0, 0) {
    // 2 + 8 weeks = 10 weeks on l1 = 2 weeks on l2
    assertEq(locking.getWeek(), 2);
    assertEq(locking.blockTillNextPeriod(), l2Week);

    _incrementBlock(l2Day * 3);

    assertEq(locking.getWeek(), 2);
    assertEq(locking.blockTillNextPeriod(), l2Day * 4);

    _incrementBlock(l2Day * 5);

    assertEq(locking.getWeek(), 3);
    assertEq(locking.blockTillNextPeriod(), l2Day * 6);

    _incrementBlock(l2Day * 8);

    assertEq(locking.getWeek(), 4);
    assertEq(locking.blockTillNextPeriod(), l2Day * 5);
  }

  function test_getWeek_whenL2StartingPointIsPositive_shouldReturnCorrectWeekNo() public l2LockingSetup(198, 190, 0) {
    // l1 week no = 198 + 2 - (190) = 10
    uint32 l1WeekNo = 10;
    // l2 week no = (198 + 2) / 5 = 40
    assertEq(locking.getWeek(), 40);
    assertEq(locking.blockTillNextPeriod(), l2Week);

    // l2WeekNo - l1WeekNo = 40 - 10 = 30
    vm.prank(mentoLabs);
    locking.setL2StartingPointWeek(30);

    // after the L2 starting point week is set, the week should be equal to the l1 week no
    assertEq(locking.getWeek(), l1WeekNo);
  }

  function test_getWeek_whenL2StartingPointIsNegative_shouldReturnCorrectWeekNo() public l2LockingSetup(18, 0, 0) {
    // l1 week no = 18 + 2 - 0 = 20
    uint32 l1WeekNo = 20;
    // l2 week no = (18 + 2) / 5 = 4
    assertEq(locking.getWeek(), 4);
    assertEq(locking.blockTillNextPeriod(), l2Week);

    // l2WeekNo - l1WeekNo = 4 - 20 = -16
    vm.prank(mentoLabs);
    locking.setL2StartingPointWeek(-16);

    // after the L2 starting point week is set, the week should be equal to the l1 week no
    assertEq(locking.getWeek(), l1WeekNo);
  }

  function test_getWeek_whenShiftIsPositive_shouldReturnCorrectWeekNo() public l2LockingSetup(18, 5, l1Day * 3) {
    // l1 week no = 18 + 2 - 5 - 1 = 19
    uint32 l1WeekNo = 14;

    // l2 week no = (18 + 2) / 5 = 4
    assertEq(locking.getWeek(), 4);
    assertEq(locking.blockTillNextPeriod(), l2Week);

    // l2WeekNo - l1WeekNo = 4 - 14 - 1 = -11
    vm.prank(mentoLabs);
    locking.setL2StartingPointWeek(-11);

    vm.prank(mentoLabs);
    locking.setL2EpochShift(l2Day * 3);

    // after the L2 starting point week and l2EpochShift are set, the timing should be equal to the l1 timing
    assertEq(locking.getWeek(), l1WeekNo);
    assertEq(locking.blockTillNextPeriod(), l2Day * 3);

    _incrementBlock(l2Day);

    assertEq(locking.getWeek(), l1WeekNo);
    assertEq(locking.blockTillNextPeriod(), l2Day * 2);

    _incrementBlock(l2Day);

    assertEq(locking.getWeek(), l1WeekNo);
    assertEq(locking.blockTillNextPeriod(), l2Day);

    _incrementBlock(l2Day);

    assertEq(locking.getWeek(), l1WeekNo + 1);
    assertEq(locking.blockTillNextPeriod(), l2Week);
  }

  function test_totalSupply_whenCalledAfterL2Transition_shouldReturnCorrectValues() public setMultisig {
    mentoToken.mint(alice, 1000000e18);

    // week no: 20
    _incrementBlock(l1Week * 18);

    vm.prank(alice);
    locking.lock(alice, alice, 1000e18, 104, 0);

    // week no: 40
    _incrementBlock(l1Week * 20);

    uint256 totalSupplyL1W40 = locking.totalSupply();
    uint256 pastTotalSupplyL1W30 = locking.getPastTotalSupply(locking.blockNumberMocked() - l1Week * 10);

    // week no: 60
    _incrementBlock(l1Week * 20);

    uint256 totalSupplyL1W60 = locking.totalSupply();
    uint256 pastTotalSupplyL1W50 = locking.getPastTotalSupply(locking.blockNumberMocked() - l1Week * 10);

    // roll back to week 40
    _reduceBlock(l1Week * 20);

    vm.prank(mentoLabs);
    locking.setL2TransitionBlock(l1Week * 40);

    vm.prank(mentoLabs);
    locking.setPaused(false);

    // 8 - 40 = -32
    vm.prank(mentoLabs);
    locking.setL2StartingPointWeek(-32);

    assertEq(locking.totalSupply(), totalSupplyL1W40);
    assertEq(locking.getPastTotalSupply(locking.blockNumberMocked() - l1Week * 10), pastTotalSupplyL1W30);

    // week no: 60
    _incrementBlock(l2Week * 20);
    assertEq(locking.totalSupply(), totalSupplyL1W60);
    assertEq(locking.getPastTotalSupply(locking.blockNumberMocked() - l2Week * 10), pastTotalSupplyL1W50);
  }

  function test_balanceOfAndGetVotes_whenCalledAfterL2Transition_shouldReturnCorrectValues() public setMultisig {
    mentoToken.mint(alice, 1000000e18);

    //  week no: 20
    _incrementBlock(l1Week * 18);

    vm.prank(alice);
    locking.lock(alice, alice, 1000e18, 104, 0);

    // week no: 40
    _incrementBlock(l1Week * 20);

    uint256 balanceOfL1W40 = locking.balanceOf(alice);
    uint256 votesL1W40 = locking.getVotes(alice);
    uint256 pastVotesL1W30 = locking.getPastVotes(alice, locking.blockNumberMocked() - l1Week * 10);

    // week no: 60
    _incrementBlock(l1Week * 20);

    uint256 balanceOfL1W60 = locking.balanceOf(alice);
    uint256 votesL1W60 = locking.getVotes(alice);
    uint256 pastVotesL1W50 = locking.getPastVotes(alice, locking.blockNumberMocked() - l1Week * 10);

    // roll back to week 40
    _reduceBlock(l1Week * 20);

    vm.prank(mentoLabs);
    locking.setL2TransitionBlock(l1Week * 40);

    vm.prank(mentoLabs);
    locking.setPaused(false);

    // 8 - 40 = -32
    vm.prank(mentoLabs);
    locking.setL2StartingPointWeek(-32);

    assertEq(locking.balanceOf(alice), balanceOfL1W40);
    assertEq(locking.getVotes(alice), votesL1W40);
    assertEq(locking.getPastVotes(alice, locking.blockNumberMocked() - l1Week * 10), pastVotesL1W30);

    // week no: 60
    _incrementBlock(l2Week * 20);
    assertEq(locking.balanceOf(alice), balanceOfL1W60);
    assertEq(locking.getVotes(alice), votesL1W60);
    assertEq(locking.getPastVotes(alice, locking.blockNumberMocked() - l2Week * 10), pastVotesL1W50);
  }

  function test_lockedAndWithdrawable_whenCalledAfterL2Transition_shouldReturnCorrectValues() public setMultisig {
    mentoToken.mint(alice, 1000000e18);

    //  week no: 20
    _incrementBlock(l1Week * 18);

    vm.prank(alice);
    locking.lock(alice, alice, 1000e18, 104, 0);

    // week no: 40
    _incrementBlock(l1Week * 20);

    uint256 lockedL1W40 = locking.locked(alice);
    uint256 withdrawableL1W40 = locking.getAvailableForWithdraw(alice);

    // week no: 60
    _incrementBlock(l1Week * 20);

    uint256 lockedL1W60 = locking.locked(alice);
    uint256 withdrawableL1W60 = locking.getAvailableForWithdraw(alice);

    // roll back to week 40
    _reduceBlock(l1Week * 20);

    vm.prank(mentoLabs);
    locking.setL2TransitionBlock(l1Week * 40);

    vm.prank(mentoLabs);
    locking.setPaused(false);

    // 8 - 40 = -32
    vm.prank(mentoLabs);
    locking.setL2StartingPointWeek(-32);

    assertEq(locking.locked(alice), lockedL1W40);
    assertEq(locking.getAvailableForWithdraw(alice), withdrawableL1W40);

    // week no: 60
    _incrementBlock(l2Week * 20);
    assertEq(locking.locked(alice), lockedL1W60);
    assertEq(locking.getAvailableForWithdraw(alice), withdrawableL1W60);
  }
}
