/* solhint-disable max-line-length */
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { BaseForkTest } from "../BaseForkTest.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { MentoToken } from "contracts/governance/MentoToken.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// used to avoid stack too deep error
struct LockingSnapshot {
  uint256 weekNo;
  uint256 totalSupply;
  uint256 pastTotalSupply;
  uint256 balance1;
  uint256 balance2;
  uint256 votingPower1;
  uint256 votingPower2;
  uint256 pastVotingPower1;
  uint256 pastVotingPower2;
  uint256 lockedBalance1;
  uint256 lockedBalance2;
  uint256 withdrawable1;
  uint256 withdrawable2;
}

contract LockingUpgradeForkTest is BaseForkTest {
  // airdrop claimers from the mainnet
  address public constant AIRDROP_CLAIMER_1 = 0x3152eE4a18ee3209524F9071A6BcAdA098f19838;
  address public constant AIRDROP_CLAIMER_2 = 0x44EB9Bf2D6B161499f1b706c331aa2Ba1d5069c7;

  uint256 public constant L1_WEEK = 7 days / 5;
  uint256 public constant L2_WEEK = 7 days;

  GovernanceFactory public governanceFactory = GovernanceFactory(0xee6CE2dbe788dFC38b8F583Da86cB9caf2C8cF5A);
  ProxyAdmin public proxyAdmin;
  Locking public locking;
  MentoGovernor public mentoGovernor;
  MentoToken public mentoToken;

  address public timelockController;
  address public newLockingImplementation;

  address public mentoLabsMultisig = makeAddr("mentoLabsMultisig");

  constructor(uint256 _chainId) BaseForkTest(_chainId) {}

  function setUp() public virtual override {
    super.setUp();
    address newProxyAdmin = 0x7DeA70fC905f5C4E8f98971761C6641D16A428c1;
    address multisig = 0x655133d8E90F8190ed5c1F0f3710F602800C0150;

    proxyAdmin = ProxyAdmin(newProxyAdmin); //governanceFactory.proxyAdmin();
    locking = governanceFactory.locking();
    timelockController = address(governanceFactory.governanceTimelock());
    mentoGovernor = governanceFactory.mentoGovernor();
    mentoToken = governanceFactory.mentoToken();

    newLockingImplementation = address(new Locking(true));
    vm.prank(multisig);
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(locking)), newLockingImplementation);

    vm.prank(timelockController);
    locking.setMentoLabsMultisig(mentoLabsMultisig);
  }

  function test_blockNoDependentCalculations_afterL2Transition_shouldWorkAsBefore() public {
    LockingSnapshot memory beforeSnapshot;
    LockingSnapshot memory afterSnapshot;

    // THU Nov-07-2024 00:00:23 +UTC
    vm.roll(28653031);
    vm.warp(1730937623);

    // move 30 weeks forward on L1
    _moveDays({ day: 30 * 7, forward: true, isL2: false });

    // Take snapshot 30 weeks after Nov 07
    beforeSnapshot = _takeSnapshot(AIRDROP_CLAIMER_1, AIRDROP_CLAIMER_2);

    // move 5 weeks forward on L1
    _moveDays({ day: 5 * 7, forward: true, isL2: false });

    // Take snapshot 35 weeks after Nov 07
    afterSnapshot = _takeSnapshot(AIRDROP_CLAIMER_1, AIRDROP_CLAIMER_2);

    // move 5 weeks backward on L1
    _moveDays({ day: 5 * 7, forward: false, isL2: false });

    uint256 blocksTillNextWeekL1 = _calculateBlocksTillNextWeek({ isL2: false });

    _simulateL2Upgrade();

    uint256 blocksTillNextWeekL2 = _calculateBlocksTillNextWeek({ isL2: true });

    // if the shift number is correct, the number of blocks till the next week should be 5 times the previous number
    assertEq(blocksTillNextWeekL2, 5 * blocksTillNextWeekL1);

    assertEq(locking.getWeek(), beforeSnapshot.weekNo);
    assertEq(locking.totalSupply(), beforeSnapshot.totalSupply);
    // the past values should be calculated using the L1 week value
    assertEq(locking.getPastTotalSupply(block.number - 3 * L1_WEEK), beforeSnapshot.pastTotalSupply);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_1), beforeSnapshot.balance1);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_2), beforeSnapshot.balance2);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_1), beforeSnapshot.votingPower1);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_2), beforeSnapshot.votingPower2);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_1, block.number - 3 * L1_WEEK), beforeSnapshot.pastVotingPower1);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_2, block.number - 3 * L1_WEEK), beforeSnapshot.pastVotingPower2);
    assertEq(locking.locked(AIRDROP_CLAIMER_1), beforeSnapshot.lockedBalance1);
    assertEq(locking.locked(AIRDROP_CLAIMER_2), beforeSnapshot.lockedBalance2);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_1), beforeSnapshot.withdrawable1);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_2), beforeSnapshot.withdrawable2);

    // move 5 weeks forward on L2
    _moveDays({ day: 5 * 7, forward: true, isL2: true });

    blocksTillNextWeekL2 = _calculateBlocksTillNextWeek({ isL2: true });

    assertEq(blocksTillNextWeekL2, 5 * blocksTillNextWeekL1);
    assertEq(locking.getWeek(), afterSnapshot.weekNo);
    assertEq(locking.totalSupply(), afterSnapshot.totalSupply);
    assertEq(locking.getPastTotalSupply(block.number - 3 * L2_WEEK), afterSnapshot.pastTotalSupply);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_1), afterSnapshot.balance1);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_2), afterSnapshot.balance2);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_1), afterSnapshot.votingPower1);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_2), afterSnapshot.votingPower2);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_1, block.number - 3 * L2_WEEK), afterSnapshot.pastVotingPower1);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_2, block.number - 3 * L2_WEEK), afterSnapshot.pastVotingPower2);
    assertEq(locking.locked(AIRDROP_CLAIMER_1), afterSnapshot.lockedBalance1);
    assertEq(locking.locked(AIRDROP_CLAIMER_2), afterSnapshot.lockedBalance2);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_1), afterSnapshot.withdrawable1);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_2), afterSnapshot.withdrawable2);

    // move 5 days forward on L2
    _moveDays({ day: 5, forward: true, isL2: true });
    // we should be at the same week (TUE around 00:00)
    assertEq(locking.getWeek(), afterSnapshot.weekNo);
    // move 1 day forward on L2 + 90 mins as buffer
    _moveDays({ day: 1, forward: true, isL2: true });
    vm.roll(block.number + 90 minutes);
    // we should be at the next week (WED around 01:30)
    assertEq(locking.getWeek(), afterSnapshot.weekNo + 1);
  }

  function test_setPaused_shouldPauseGovernance() public {
    _lockTokensForGovernance(AIRDROP_CLAIMER_1, 10_000_000e18);

    vm.prank(mentoLabsMultisig);
    locking.setPaused(true);

    vm.prank(AIRDROP_CLAIMER_1);
    vm.expectRevert("locking is paused");
    mentoGovernor.propose(new address[](1), new uint256[](1), new bytes[](1), "Test proposal");

    vm.prank(mentoLabsMultisig);
    locking.setPaused(false);

    vm.prank(AIRDROP_CLAIMER_1);
    uint256 proposalId = mentoGovernor.propose(new address[](1), new uint256[](1), new bytes[](1), "Test proposal");

    _moveDays(1, true, false);

    vm.prank(mentoLabsMultisig);
    locking.setPaused(true);

    vm.prank(AIRDROP_CLAIMER_1);
    vm.expectRevert("locking is paused");
    mentoGovernor.castVote(proposalId, 1);
  }

  function test_governance_afterL2Transition_shouldWorkAsBefore() public {
    _simulateL2Upgrade();

    _moveDays(30 * 7, true, true);

    uint256 votingPower1 = locking.getVotes(AIRDROP_CLAIMER_1);
    uint256 votingPower2 = locking.getVotes(AIRDROP_CLAIMER_2);

    uint256 lockId = _lockTokensForGovernance(AIRDROP_CLAIMER_1, 1_000_000e18);

    assertEq(locking.getVotes(AIRDROP_CLAIMER_1), votingPower1 + 1_000_000e18);

    vm.prank(AIRDROP_CLAIMER_1);
    locking.delegateTo(lockId, AIRDROP_CLAIMER_2);

    assertEq(locking.getVotes(AIRDROP_CLAIMER_1), votingPower1);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_2), votingPower2 + 1_000_000e18);

    vm.prank(AIRDROP_CLAIMER_1);
    locking.relock(lockId, AIRDROP_CLAIMER_1, 1_000_000e18, 1, 103);

    assertEq(locking.getVotes(AIRDROP_CLAIMER_1), votingPower1 + 1_000_000e18);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_2), votingPower2);

    vm.prank(AIRDROP_CLAIMER_1);
    uint256 proposalId = mentoGovernor.propose(new address[](1), new uint256[](1), new bytes[](1), "Test proposal");

    _moveDays(1, true, true);

    vm.prank(AIRDROP_CLAIMER_1);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(AIRDROP_CLAIMER_2);
    mentoGovernor.castVote(proposalId, 2);

    _moveDays(5, true, true);

    mentoGovernor.queue(proposalId);

    _moveDays(2, true, true);

    mentoGovernor.execute(proposalId);
  }

  // used to give locker enough power to be able to propose
  function _lockTokensForGovernance(address locker, uint96 amount) internal returns (uint256 lockId) {
    deal(address(mentoToken), locker, amount);

    vm.prank(locker);
    mentoToken.approve(address(locking), amount);

    vm.prank(locker);
    lockId = locking.lock(locker, locker, amount, 104, 0);

    vm.roll(block.number + 1);
  }

  // takes a snapshot of the locking contract at current block
  function _takeSnapshot(address claimer1, address claimer2) internal view returns (LockingSnapshot memory snapshot) {
    snapshot.weekNo = locking.getWeek();
    snapshot.totalSupply = locking.totalSupply();
    snapshot.pastTotalSupply = locking.getPastTotalSupply(block.number - 3 * L1_WEEK);
    snapshot.balance1 = locking.balanceOf(claimer1);
    snapshot.balance2 = locking.balanceOf(claimer2);
    snapshot.votingPower1 = locking.getVotes(claimer1);
    snapshot.votingPower2 = locking.getVotes(claimer2);
    snapshot.pastVotingPower1 = locking.getPastVotes(claimer1, block.number - 3 * L1_WEEK);
    snapshot.pastVotingPower2 = locking.getPastVotes(claimer2, block.number - 3 * L1_WEEK);
    snapshot.lockedBalance1 = locking.locked(claimer1);
    snapshot.lockedBalance2 = locking.locked(claimer2);
    snapshot.withdrawable1 = locking.getAvailableForWithdraw(claimer1);
    snapshot.withdrawable2 = locking.getAvailableForWithdraw(claimer2);
  }

  // returns the number of blocks till the next week
  // by calculating the first block of the next week and substracting the current block
  function _calculateBlocksTillNextWeek(bool isL2) internal view returns (uint256) {
    if (isL2) {
      return
        L2_WEEK *
        uint256(int256(locking.getWeek()) + locking.l2StartingPointWeek() + 1) +
        locking.l2EpochShift() -
        block.number;
    } else {
      return L1_WEEK * (locking.getWeek() + locking.startingPointWeek() + 1) + locking.L1_EPOCH_SHIFT() - block.number;
    }
  }

  // simulates the L2 upgrade by setting the necessary parameters
  function _simulateL2Upgrade() internal {
    vm.prank(mentoLabsMultisig);
    locking.setL2TransitionBlock(block.number);
    vm.prank(mentoLabsMultisig);
    locking.setL2StartingPointWeek(-1);
    vm.prank(mentoLabsMultisig);
    locking.setL2EpochShift(144896);
    vm.prank(mentoLabsMultisig);
    locking.setPaused(false);
  }

  // move days forward or backward on L1 or L2
  function _moveDays(uint256 day, bool forward, bool isL2) internal {
    uint256 ts = vm.getBlockTimestamp();
    uint256 height = vm.getBlockNumber();

    uint256 newTs = forward ? ts + day * 1 days : ts - day * 1 days;

    uint256 blockChange = isL2 ? (day * 1 days) : ((day * 1 days) / 5);
    uint256 newHeight = forward ? height + blockChange : height - blockChange;

    vm.warp(newTs);
    vm.roll(newHeight);
  }
}
