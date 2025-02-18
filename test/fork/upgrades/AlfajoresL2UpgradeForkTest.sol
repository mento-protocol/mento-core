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

import "forge-std/console2.sol";

struct LockingSnapshot {
  uint256 weekNo;
  uint256 totalSupply;
  uint256 pastTotalSupply;
  uint256 balance;
  uint256 votingPower;
  uint256 pastVotingPower;
  uint256 lockedBalance;
  uint256 withdrawable;
}

contract AlfajoresL2UpgradeForkTest is BaseForkTest {
  /*
    Alfajores L2 fork happened at block 26384000 (week 19), Sep-26-2024 08:28:40 AM +UTC

    Week 20 began at block 26459244 (1727414564, Fri, 27 Sep 2024 05:22:44 +0000))
    Week 21 began at block 26580204 (1727535524, Sat, 28 Sep 2024 14:58:44 +0000))
    Week 22 began at block 26701164 (1727656484, Mon, 30 Sep 2024 00:34:44 +0000))
    ...and so on
  */
  uint256 public constant L1_WEEK = 7 days / 5;
  uint256 public constant L2_WEEK = 7 days;
  uint256 public constant L2_UPGRADE_BLOCK = 26384000; // 1727339320, Sep-26-2024 08:28:40 AM +UTC

  address public PROXY_ADMIN = 0x6d336330947ec0895C58a46fEFc7A194207Ad914;
  address public NEW_LOCKING_IMPLEMENTATION = 0x7aca85DDdD5f6B18f03d189408CE15020944a0cf;
  address public MENTOLABS_MULTISIG = 0x56fD3F2bEE130e9867942D0F463a16fBE49B8d81;

  /*
    Account with 2 Locks on Alfajores

    Initial lock of 5000 MENTO @ block 25409438 (week 11) (1722455844, Jul-31-2024 07:57:24 PM UTC), slope=104 cliff=0
    Re-lock of 500 MENTO @ block 32532535 (week "70") (1733487855, Dec-06-2024 12:24:15 PM UTC), slope=46 cliff=0

    Withdrawal schedule based on week number:
    Week 20 , block# 26459244 => 432
    Week 21 , block# 26580204 => 480
    Week 22 , block# 26701164 => 528
    Week 23 , block# 26822124 => 576
    Week 24 , block# 26943084 => 625
    Week 25 , block# 27064044 => 673
    Week 26 , block# 27185004 => 721
    Week 27 , block# 27305964 => 769
    Week 28 , block# 27426924 => 817
    Week 29 , block# 27547884 => 865
    Week 30 , block# 27668844 => 913
  */
  address ACCOUNT_WITH_LOCK = 0x613A91104b92b439Ed355E94336E807b3b70402D;

  GovernanceFactory public governanceFactory = GovernanceFactory(0x96Fe03DBFEc1EB419885a01d2335bE7c1a45e33b);
  ProxyAdmin public proxyAdmin;
  Locking public locking;
  MentoGovernor public mentoGovernor;
  MentoToken public mentoToken;
  address public timelockController;

  constructor(uint256 _chainId) BaseForkTest(_chainId) {}

  function setUp() public virtual override {
    // super.setUp();

    locking = governanceFactory.locking();
    timelockController = address(governanceFactory.governanceTimelock());
    mentoGovernor = governanceFactory.mentoGovernor();
    mentoToken = governanceFactory.mentoToken();
    proxyAdmin = ProxyAdmin(PROXY_ADMIN);

    // Pre-checks, locking is upgraded and multisig is set
    // require(
    //   proxyAdmin.getProxyImplementation((ITransparentUpgradeableProxy(address(locking)))) == NEW_LOCKING_IMPLEMENTATION, 
    //   "Locking implementation is not correctly set"
    // );
    // require(locking.mentoLabsMultisig() == MENTOLABS_MULTISIG, "MentoLabs multisig is not correctly set");
  }

  function upgradeLockingImplementation() internal {
    // For simulating the upgrade in the past, deploy the new locking using the old proxy admin
    // which was owned by the timelockcontroller, not the multisig
    address newLockingImpl = address(new Locking(true));
    ProxyAdmin oldProxyAdmin = ProxyAdmin(0xD0e0eeEF2325A5518104Af1B5ab2395EfEa900a6);

    vm.startPrank(timelockController);
    oldProxyAdmin.upgrade(ITransparentUpgradeableProxy(address(locking)), newLockingImpl);
    locking.setMentoLabsMultisig(MENTOLABS_MULTISIG);
    vm.stopPrank();
  }

  function test_pretendUpgradeWasDoneInThePast() public {
    // Travel back to the past and try to do the L2 a few blocks after the L2 upgrade block,
    // before the week calculations went crazy.
    // env FOUNDRY_PROFILE=fork-tests forge test --match-contract Alfajores_L2UpgradeForkTest --match-test test_pretendUpgradeWasDoneInThePast --fork-url $ALFAJORES_RPC_URL --fork-block-number 26384000 -vvv

    // Upgrade the locking implementation, as it was not yet deployed back then
    upgradeLockingImplementation();

    // Take snapshots of the initial state before the upgrade
    console2.log("==========\t\tBefore L2 Upgrade\t\t==========\n");
    assertEq(vm.getBlockNumber(), L2_UPGRADE_BLOCK);
    assertEq(locking.getWeek(), 19);
    uint256 blocksTillWeek20BeforeUpgrade = _calculateBlocksTillNextWeek({ isL2: false });
    LockingSnapshot memory snapshotBeforeUpgradeWeek19 = _takeSnapshot(ACCOUNT_WITH_LOCK);
    printSnapshot(snapshotBeforeUpgradeWeek19);
    // Another one on week 20
    _moveBlocks({ blocks: blocksTillWeek20BeforeUpgrade, forward: true, isL2: false });
    assertEq(locking.getWeek(), 20);
    LockingSnapshot memory snapshotBeforeUpgradeWeek20 = _takeSnapshot(ACCOUNT_WITH_LOCK);
    uint256 blocksTillWeek21BeforeUpgrade = _calculateBlocksTillNextWeek({ isL2: false });
    printSnapshot(snapshotBeforeUpgradeWeek20);
    // Go back to week 19
    _moveBlocks({ blocks: blocksTillWeek20BeforeUpgrade, forward: false, isL2: false });
    assertEq(vm.getBlockNumber(), L2_UPGRADE_BLOCK);

    console2.log(unicode"=== 🚀🚀🚀 L2 Upgrade at block %d (week %d) ===\n", vm.getBlockNumber(), locking.getWeek());
    setL2transitionBlock(vm.getBlockNumber());
    assertTrue(locking.paused());
    setL2StartingPointWeek(24);
    setL2EpochShift(149020);
    unpauseLocking();
    assertFalse(locking.paused());

    console2.log("==========\t\tAfter L2 Upgrade\t\t==========");
    uint256 blocksTillWeek20AfterUpgrade = _calculateBlocksTillNextWeek({ isL2: true });
    assertEq(blocksTillWeek20AfterUpgrade, 5*blocksTillWeek20BeforeUpgrade);
    console2.log(unicode"👀 blocksTilNextWeek before upgrade", blocksTillWeek20BeforeUpgrade);
    console2.log(unicode"🤝 blocksTilNextWeek after upgrade %d (5 * %d)\n", blocksTillWeek20AfterUpgrade, blocksTillWeek20BeforeUpgrade);

    uint256 beforeNextWeek = blocksTillWeek20AfterUpgrade - 1;
    _moveBlocks({ blocks: beforeNextWeek, forward: true, isL2: true });
    assertAccountSnapshotsEqual(snapshotBeforeUpgradeWeek19, _takeSnapshot(ACCOUNT_WITH_LOCK));
    console2.log(unicode"Week 19 consistency kept after upgrade ✅\n");
    // Advance to week 20
    _moveBlocks({ blocks: 1, forward: true, isL2: true });
    assertAccountSnapshotsEqual(snapshotBeforeUpgradeWeek20, _takeSnapshot(ACCOUNT_WITH_LOCK));
    assertEq(_calculateBlocksTillNextWeek({ isL2: true }), 5*blocksTillWeek21BeforeUpgrade);
    console2.log(unicode"Week 20 consistency kept after upgrade ✅");
  }

  function test_doUpgradeNow() public {
    uint256 executionBlock = 38591100; // 1739546420 (Fri, 14 Feb 2025 15:20:20 +0000)
    assertEq(vm.getBlockNumber(), executionBlock);
    assertEq(locking.getWeek(), 120);

    uint256 blocksTilNextWeekBeforeUpgrade = _calculateBlocksTillNextWeek({ isL2: false });
    console2.log("==========\t\tBefore L2 Upgrade\t\t==========");
    console2.log("Block: %d", vm.getBlockNumber());
    console2.log("Week: %d", locking.getWeek());
    console2.log("Blocks til next week: %d\n", blocksTilNextWeekBeforeUpgrade);

    address LOCK_FULLY_UNLOCKED = 0x613A91104b92b439Ed355E94336E807b3b70402D; // https://alfajores.celoscan.io/tx/0x6423cd57437e64c6fd1bfe47cdf58fd87538cbee2c6c9241f60862aaead1656d#eventlog
    address LOCK_WITH_5_WEEKS_LEFT = 0x26aA945acE8347bEb3EFC34ef895739780d46396; // https://alfajores.celoscan.io/tx/0x186ae51520b78120a19ed4bc540bb6bd4b536a66e2a69f13d2ec408f05d98595#eventlog
    address FRESH_LOCK_WITH_MAX_SLOPE = 0xC616881706AC87306077c6e032103467cDA57020;
    LockingSnapshot memory fullyUnlockedBeforeUpgrade = _takeSnapshot(LOCK_FULLY_UNLOCKED);
    LockingSnapshot memory twoWeeksLeftBeforeUpgrade = _takeSnapshot(LOCK_WITH_5_WEEKS_LEFT);
    LockingSnapshot memory maxSlopeBeforeUpgrade = _takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE);

    // ========= UPGRADE =========
    console2.log(unicode"=== 🚀🚀🚀 L2 Upgrade at block %d (week %d) ===\n", vm.getBlockNumber(), locking.getWeek());
    setL2transitionBlock(vm.getBlockNumber());
    assertTrue(locking.paused());

    setL2StartingPointWeek(-57);
    setL2EpochShift(309420);

    unpauseLocking();
    assertFalse(locking.paused());
    // ========= UPGRADE =========

    console2.log("==========\t\tAfter L2 Upgrade\t\t==========");
    assertEq(locking.getWeek(), 120);

    console2.log("lock: %d", vm.getBlockNumber());
    console2.log("Week: %d", locking.getWeek());

    uint256 blocksTilNextWeekAfterUpgrade = _calculateBlocksTillNextWeek({ isL2: true });
    assertEq(blocksTilNextWeekAfterUpgrade, 5*blocksTilNextWeekBeforeUpgrade);
    console2.log(unicode"🤝 blocksTilNextWeek after upgrade %d (5 * %d)\n", blocksTilNextWeekAfterUpgrade, blocksTilNextWeekBeforeUpgrade);


    LockingSnapshot memory fullyUnlockedAfterUpgrade = _takeSnapshot(LOCK_FULLY_UNLOCKED);
    LockingSnapshot memory fiveWeeksLeftAfterUpgrade = _takeSnapshot(LOCK_WITH_5_WEEKS_LEFT);
    LockingSnapshot memory maxSlopeAfterUpgrade = _takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE);
    assertAccountSnapshotsEqual(fullyUnlockedBeforeUpgrade, fullyUnlockedAfterUpgrade);
    assertAccountSnapshotsEqual(twoWeeksLeftBeforeUpgrade, fiveWeeksLeftAfterUpgrade);
    assertAccountSnapshotsEqual(maxSlopeBeforeUpgrade, maxSlopeAfterUpgrade);

    // Time travel right before next week
    uint256 beforeNextWeek = blocksTilNextWeekAfterUpgrade - 1;
    _moveBlocks({ blocks: beforeNextWeek, forward: true, isL2: true });
    assertEq(locking.getWeek(), 120);
    // Snapshots are still the same
    assertAccountSnapshotsEqual(fullyUnlockedBeforeUpgrade, _takeSnapshot(LOCK_FULLY_UNLOCKED));
    assertAccountSnapshotsEqual(twoWeeksLeftBeforeUpgrade, _takeSnapshot(LOCK_WITH_5_WEEKS_LEFT));
    assertAccountSnapshotsEqual(maxSlopeBeforeUpgrade, _takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE));

    // Move to next week
    console2.log("=== Lock with 5 weeks left ===");
    printSnapshot(fiveWeeksLeftAfterUpgrade);

    console2.log("=== Lock with Max Slope ===");
    printSnapshot(maxSlopeAfterUpgrade);

    _moveBlocks({ blocks: 1, forward: true, isL2: true });

    printSnapshot(_takeSnapshot(LOCK_WITH_5_WEEKS_LEFT));
    printSnapshot(_takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE));

    // 4 more weeks forward, the 5 week lock should be fully unlocked
    _moveDays({ day: 4 * 7, forward: true, isL2: true });
    printSnapshot(_takeSnapshot(LOCK_WITH_5_WEEKS_LEFT));
    printSnapshot(_takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE));
  }

  function test_actualUpgrade() public {
    // uint256 executionBlock = 38591100; // 1739546420 (Fri, 14 Feb 2025 15:20:20 +0000)
    // assertEq(vm.getBlockNumber(), executionBlock);
    console2.log("Running at block", vm.getBlockNumber());
    unpauseLocking();
    assertEq(locking.getWeek(), 120);

    uint256 blocksTilNextWeekBeforeUpgrade = _calculateBlocksTillNextWeek({ isL2: false });
    console2.log("==========\t\tBefore L2 Upgrade\t\t==========");
    console2.log("Block: %d", vm.getBlockNumber());
    console2.log("Week: %d", locking.getWeek());
    console2.log("Blocks til next week: %d\n", blocksTilNextWeekBeforeUpgrade);

    address LOCK_FULLY_UNLOCKED = 0x613A91104b92b439Ed355E94336E807b3b70402D; // https://alfajores.celoscan.io/tx/0x6423cd57437e64c6fd1bfe47cdf58fd87538cbee2c6c9241f60862aaead1656d#eventlog
    address LOCK_WITH_5_WEEKS_LEFT = 0x26aA945acE8347bEb3EFC34ef895739780d46396; // https://alfajores.celoscan.io/tx/0x186ae51520b78120a19ed4bc540bb6bd4b536a66e2a69f13d2ec408f05d98595#eventlog
    address FRESH_LOCK_WITH_MAX_SLOPE = 0xC616881706AC87306077c6e032103467cDA57020;
    LockingSnapshot memory fullyUnlockedBeforeUpgrade = _takeSnapshot(LOCK_FULLY_UNLOCKED);
    LockingSnapshot memory twoWeeksLeftBeforeUpgrade = _takeSnapshot(LOCK_WITH_5_WEEKS_LEFT);
    LockingSnapshot memory maxSlopeBeforeUpgrade = _takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE);

    // ========= UPGRADE =========
    // console2.log(unicode"=== 🚀🚀🚀 L2 Upgrade at block %d (week %d) ===\n", vm.getBlockNumber(), locking.getWeek());
    // setL2transitionBlock(vm.getBlockNumber());
    // assertTrue(locking.paused());

    // setL2StartingPointWeek(-57);
    // setL2EpochShift(309420);

    // assertFalse(locking.paused());
    // ========= UPGRADE =========

    console2.log("==========\t\tAfter L2 Upgrade\t\t==========");
    assertEq(locking.getWeek(), 120);

    console2.log("lock: %d", vm.getBlockNumber());
    console2.log("Week: %d", locking.getWeek());

    uint256 blocksTilNextWeekAfterUpgrade = _calculateBlocksTillNextWeek({ isL2: true });
    // assertEq(blocksTilNextWeekAfterUpgrade, 5*blocksTilNextWeekBeforeUpgrade);
    console2.log(unicode"🤝 blocksTilNextWeek after upgrade %d (5 * %d)\n", blocksTilNextWeekAfterUpgrade, blocksTilNextWeekBeforeUpgrade);


    LockingSnapshot memory fullyUnlockedAfterUpgrade = _takeSnapshot(LOCK_FULLY_UNLOCKED);
    LockingSnapshot memory fiveWeeksLeftAfterUpgrade = _takeSnapshot(LOCK_WITH_5_WEEKS_LEFT);
    LockingSnapshot memory maxSlopeAfterUpgrade = _takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE);
    assertAccountSnapshotsEqual(fullyUnlockedBeforeUpgrade, fullyUnlockedAfterUpgrade);
    assertAccountSnapshotsEqual(twoWeeksLeftBeforeUpgrade, fiveWeeksLeftAfterUpgrade);
    assertAccountSnapshotsEqual(maxSlopeBeforeUpgrade, maxSlopeAfterUpgrade);

    // Time travel right before next week
    uint256 beforeNextWeek = blocksTilNextWeekAfterUpgrade - 1;
    _moveBlocks({ blocks: beforeNextWeek, forward: true, isL2: true });
    assertEq(locking.getWeek(), 120);
    // Snapshots are still the same
    assertAccountSnapshotsEqual(fullyUnlockedBeforeUpgrade, _takeSnapshot(LOCK_FULLY_UNLOCKED));
    assertAccountSnapshotsEqual(twoWeeksLeftBeforeUpgrade, _takeSnapshot(LOCK_WITH_5_WEEKS_LEFT));
    assertAccountSnapshotsEqual(maxSlopeBeforeUpgrade, _takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE));

    // Move to next week
    console2.log("=== Lock with 5 weeks left ===");
    printSnapshot(fiveWeeksLeftAfterUpgrade);

    console2.log("=== Lock with Max Slope ===");
    printSnapshot(maxSlopeAfterUpgrade);

    _moveBlocks({ blocks: 1, forward: true, isL2: true });

    printSnapshot(_takeSnapshot(LOCK_WITH_5_WEEKS_LEFT));
    printSnapshot(_takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE));

    // 4 more weeks forward, the 5 week lock should be fully unlocked
    _moveDays({ day: 4 * 7, forward: true, isL2: true });
    printSnapshot(_takeSnapshot(LOCK_WITH_5_WEEKS_LEFT));
    printSnapshot(_takeSnapshot(FRESH_LOCK_WITH_MAX_SLOPE));
  }

  // takes a snapshot of the locking contract at current block
  function _takeSnapshot(address claimer1) internal view returns (LockingSnapshot memory snapshot) {
    snapshot.weekNo = locking.getWeek();
    snapshot.totalSupply = locking.totalSupply();
    // snapshot.pastTotalSupply = locking.getPastTotalSupply(block.number - 3 * L1_WEEK);
    snapshot.balance = locking.balanceOf(claimer1);
    snapshot.votingPower = locking.getVotes(claimer1);
    // snapshot.pastVotingPower = locking.getPastVotes(claimer1, block.number - 3 * L1_WEEK);
    snapshot.lockedBalance = locking.locked(claimer1);
    snapshot.withdrawable = locking.getAvailableForWithdraw(claimer1);
  }

  function assertAccountSnapshotsEqual(LockingSnapshot memory a, LockingSnapshot memory b) internal pure {
    assertEq(a.weekNo, b.weekNo);
    assertEq(a.balance, b.balance);
    assertEq(a.votingPower, b.votingPower);
    assertEq(a.lockedBalance, b.lockedBalance);
    assertEq(a.withdrawable, b.withdrawable);
  }

  function assertFullSnapshotsEqual(LockingSnapshot memory a, LockingSnapshot memory b) internal pure {
    assertEq(a.weekNo, b.weekNo);
    assertEq(a.balance, b.balance);
    assertEq(a.votingPower, b.votingPower);
    assertEq(a.lockedBalance, b.lockedBalance);
    assertEq(a.withdrawable, b.withdrawable);

    // assertEq(a.totalSupply, b.totalSupply);
    // assertEq(a.pastTotalSupply, b.pastTotalSupply);
  }

  function printSnapshot(LockingSnapshot memory snapshot) internal view {
    console2.log("=== Snapshot at Week", snapshot.weekNo, "===");
    console2.log("Block #: \t\t\t", vm.getBlockNumber());
    console2.log("Block ts: \t\t\t", vm.getBlockTimestamp());
    console2.log("Total Supply: \t\t", snapshot.totalSupply / 1e18);
    console2.log("Balance: \t\t\t", snapshot.balance / 1e18);
    console2.log("Voting Power: \t\t", snapshot.votingPower / 1e18);
    console2.log("Locked Balance: \t\t", snapshot.lockedBalance / 1e18);
    console2.log("Withdrawable: \t\t", snapshot.withdrawable / 1e18);
    console2.log("\n");
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

  function setL2transitionBlock(uint256 _block) internal {
    vm.prank(MENTOLABS_MULTISIG);
    locking.setL2TransitionBlock(_block);
  }

  function setL2StartingPointWeek(int256 _week) internal {
    vm.prank(MENTOLABS_MULTISIG);
    locking.setL2StartingPointWeek(_week);
  }

  function setL2EpochShift(uint32 _shift) internal {
    vm.prank(MENTOLABS_MULTISIG);
    locking.setL2EpochShift(_shift);
  }

  function unpauseLocking() internal {
    vm.prank(MENTOLABS_MULTISIG);
    locking.setPaused(false);
  }

  // simulates the L2 upgrade by setting the necessary parameters
  function _simulateL2Upgrade() internal {
    vm.prank(MENTOLABS_MULTISIG);
    locking.setL2TransitionBlock(block.number);
    vm.prank(MENTOLABS_MULTISIG);
    locking.setL2StartingPointWeek(-1);
    vm.prank(MENTOLABS_MULTISIG);
    locking.setL2EpochShift(144896);
    vm.prank(MENTOLABS_MULTISIG);
    locking.setPaused(false);
  }

  function _moveBlocks(uint256 blocks, bool forward, bool isL2) internal {
    uint256 ts = vm.getBlockTimestamp();
    uint256 height = vm.getBlockNumber();

    uint256 tsMultiplier = 1 seconds * (isL2 ? 1 : 5);
    uint256 newTs = forward ? ts + blocks * tsMultiplier : ts - blocks * tsMultiplier;
    uint256 newHeight = forward ? height + blocks : height - blocks;

    vm.warp(newTs);
    vm.roll(newHeight);

    if (forward) {
      console2.log(unicode"=== ⏩⏩⏩ Time travel forward", blocks, "blocks ===");
    } else {
      console2.log(unicode"=== ⏪⏪⏪ Time travel backward", blocks, "blocks ===");
    }
    console2.log("=== block %d | ts %d | week %d", vm.getBlockNumber(), vm.getBlockTimestamp(), locking.getWeek());
    console2.log("\n");
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

    if (forward) {
      console2.log(unicode"=== ⏩⏩⏩ Time travel forward", day, "days ===");
    } else {
      console2.log(unicode"=== ⏪⏪⏪ Time travel backward", day, "days ===");
    }
    console2.log("=== block %d | ts %d | week %d", vm.getBlockNumber(), vm.getBlockTimestamp(), locking.getWeek());
    console2.log("\n");
  }
}
