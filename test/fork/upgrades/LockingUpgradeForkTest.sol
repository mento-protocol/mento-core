// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { BaseForkTest } from "../BaseForkTest.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/console.sol";

// used to avoid stack too deep error
struct Balances {
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
  address public timelockController;
  address public newLockingImplementation;

  address public mentoLabsMultisig = makeAddr("mentoLabsMultisig");

  constructor(uint256 _chainId) BaseForkTest(_chainId) {}

  function setUp() public virtual override {
    super.setUp();
    proxyAdmin = governanceFactory.proxyAdmin();
    locking = governanceFactory.locking();
    timelockController = address(governanceFactory.governanceTimelock());

    newLockingImplementation = address(new Locking());
    vm.prank(timelockController);
    proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(locking)), newLockingImplementation);
  }

  function test_upgrade() public {
    Balances memory beforeBalances;
    Balances memory afterBalances;

    vm.prank(timelockController);
    locking.setMentoLabsMultisig(mentoLabsMultisig);

    // THU Nov-07-2024 12:00:23 AM +UTC
    vm.roll(28653031);
    vm.warp(1730937623);

    // move 3 weeks forward on L1
    moveDays(3 * 7, true, false);

    uint256 weekNoBefore = locking.getWeek();

    beforeBalances.totalSupply = locking.totalSupply();
    beforeBalances.pastTotalSupply = locking.getPastTotalSupply(block.number - 3 * L1_WEEK);
    beforeBalances.balance1 = locking.balanceOf(AIRDROP_CLAIMER_1);
    beforeBalances.balance2 = locking.balanceOf(AIRDROP_CLAIMER_2);
    beforeBalances.votingPower1 = locking.getVotes(AIRDROP_CLAIMER_1);
    beforeBalances.votingPower2 = locking.getVotes(AIRDROP_CLAIMER_2);
    beforeBalances.pastVotingPower1 = locking.getPastVotes(AIRDROP_CLAIMER_1, block.number - 3 * L1_WEEK);
    beforeBalances.pastVotingPower2 = locking.getPastVotes(AIRDROP_CLAIMER_2, block.number - 3 * L1_WEEK);
    beforeBalances.lockedBalance1 = locking.locked(AIRDROP_CLAIMER_1);
    beforeBalances.lockedBalance2 = locking.locked(AIRDROP_CLAIMER_2);
    beforeBalances.withdrawable1 = locking.getAvailableForWithdraw(AIRDROP_CLAIMER_1);
    beforeBalances.withdrawable2 = locking.getAvailableForWithdraw(AIRDROP_CLAIMER_2);

    // move 5 weeks forward on L1
    moveDays(5 * 7, true, false);

    afterBalances.totalSupply = locking.totalSupply();
    afterBalances.pastTotalSupply = locking.getPastTotalSupply(block.number - 3 * L1_WEEK);
    afterBalances.balance1 = locking.balanceOf(AIRDROP_CLAIMER_1);
    afterBalances.balance2 = locking.balanceOf(AIRDROP_CLAIMER_2);
    afterBalances.votingPower1 = locking.getVotes(AIRDROP_CLAIMER_1);
    afterBalances.votingPower2 = locking.getVotes(AIRDROP_CLAIMER_2);
    afterBalances.pastVotingPower1 = locking.getPastVotes(AIRDROP_CLAIMER_1, block.number - 3 * L1_WEEK);
    afterBalances.pastVotingPower2 = locking.getPastVotes(AIRDROP_CLAIMER_2, block.number - 3 * L1_WEEK);
    afterBalances.lockedBalance1 = locking.locked(AIRDROP_CLAIMER_1);
    afterBalances.lockedBalance2 = locking.locked(AIRDROP_CLAIMER_2);
    afterBalances.withdrawable1 = locking.getAvailableForWithdraw(AIRDROP_CLAIMER_1);
    afterBalances.withdrawable2 = locking.getAvailableForWithdraw(AIRDROP_CLAIMER_2);

    // move 35 days backward on L1
    moveDays(35, false, false);

    uint256 blocksTillNextWeek = ((L1_WEEK * (locking.getWeek() + locking.startingPointWeek() + 1)) + 89964) -
      block.number;

    // simulate L2 upgrade
    vm.prank(mentoLabsMultisig);
    locking.setL2TransitionBlock(block.number);

    vm.prank(mentoLabsMultisig);
    locking.setL2StartingPointWeek(20);

    vm.prank(mentoLabsMultisig);
    locking.setL2Shift(507776);

    vm.prank(mentoLabsMultisig);
    locking.setPaused(false);

    uint256 blocksTillNextWeek2 = ((L2_WEEK * (locking.getWeek() + uint256(locking.l2StartingPointWeek()) + 1)) +
      507776) - block.number;

    // if the shift number is correct, the number of blocks till the next week should be 5 times the previous number
    assertEq(blocksTillNextWeek2, 5 * blocksTillNextWeek);

    assertEq(locking.getWeek(), weekNoBefore);
    assertEq(locking.totalSupply(), beforeBalances.totalSupply);
    // the past values should be calculated using the L1 week value
    assertEq(locking.getPastTotalSupply(block.number - 3 * L1_WEEK), beforeBalances.pastTotalSupply);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_1), beforeBalances.balance1);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_2), beforeBalances.balance2);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_1), beforeBalances.votingPower1);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_2), beforeBalances.votingPower2);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_1, block.number - 3 * L1_WEEK), beforeBalances.pastVotingPower1);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_2, block.number - 3 * L1_WEEK), beforeBalances.pastVotingPower2);
    assertEq(locking.locked(AIRDROP_CLAIMER_1), beforeBalances.lockedBalance1);
    assertEq(locking.locked(AIRDROP_CLAIMER_2), beforeBalances.lockedBalance2);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_1), beforeBalances.withdrawable1);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_2), beforeBalances.withdrawable2);

    // // move 5 weeks forward on L2
    moveDays(5 * 7, true, true);

    assertEq(locking.getWeek(), weekNoBefore + 5);

    blocksTillNextWeek2 =
      ((L2_WEEK * (locking.getWeek() + uint256(locking.l2StartingPointWeek()) + 1)) + 507776) -
      block.number;

    assertEq(blocksTillNextWeek2, 5 * blocksTillNextWeek);
    assertEq(locking.totalSupply(), afterBalances.totalSupply);
    assertEq(locking.getPastTotalSupply(block.number - 3 * L2_WEEK), afterBalances.pastTotalSupply);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_1), afterBalances.balance1);
    assertEq(locking.balanceOf(AIRDROP_CLAIMER_2), afterBalances.balance2);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_1), afterBalances.votingPower1);
    assertEq(locking.getVotes(AIRDROP_CLAIMER_2), afterBalances.votingPower2);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_1, block.number - 3 * L2_WEEK), afterBalances.pastVotingPower1);
    assertEq(locking.getPastVotes(AIRDROP_CLAIMER_2, block.number - 3 * L2_WEEK), afterBalances.pastVotingPower2);
    assertEq(locking.locked(AIRDROP_CLAIMER_1), afterBalances.lockedBalance1);
    assertEq(locking.locked(AIRDROP_CLAIMER_2), afterBalances.lockedBalance2);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_1), afterBalances.withdrawable1);
    assertEq(locking.getAvailableForWithdraw(AIRDROP_CLAIMER_2), afterBalances.withdrawable2);
  }

  // move days forward or backward on L1 or L2
  function moveDays(uint256 day, bool forward, bool isL2) public {
    uint256 ts = vm.getBlockTimestamp();
    uint256 height = vm.getBlockNumber();

    uint256 newTs = forward ? ts + day * 1 days : ts - day * 1 days;
    uint256 blockChange = isL2 ? (day * 1 days) : ((day * 1 days) / 5);
    uint256 newHeight = forward ? height + blockChange : height - blockChange;
    vm.warp(newTs);
    vm.roll(newHeight);

    ts = vm.getBlockTimestamp();
    height = vm.getBlockNumber();
  }
}
