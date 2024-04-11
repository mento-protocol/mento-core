// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length, max-states-count

import { TestSetup } from "../TestSetup.sol";
import { Vm } from "forge-std-next/Vm.sol";
import { VmExtension } from "test/utils/VmExtension.sol";

import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { MentoToken } from "contracts/governance/MentoToken.sol";
import { Airgrab } from "contracts/governance/Airgrab.sol";
import { Emission } from "contracts/governance/Emission.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";

import { Proposals } from "./Proposals.sol";
import { Arrays } from "test/utils/Arrays.sol";

import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import "forge-std-next/console.sol";

contract GovernanceGasTest is TestSetup {
  using VmExtension for Vm;

  GovernanceFactory public factory;

  ProxyAdmin public proxyAdmin;
  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public governanceTimelock;
  address public governanceTimelockAddress;
  MentoGovernor public mentoGovernor;
  Locking public locking;

  address public celoGovernance = makeAddr("CeloGovernance");
  address public watchdogMultisig = makeAddr("WatchdogMultisig");
  address public mentoLabsMultisig = makeAddr("MentoLabsMultisig");
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809;

  uint256 public proposalCreationGas = 500_000;
  uint256 public proposalQueueGas = 200_000;
  uint256 public proposalExecutionGas = 200_000;
  uint256 public voteGas = 100_000;

  modifier s_attack() {
    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(alice, 10_000e18);

    vm.prank(governanceTimelockAddress);
    mentoToken.transfer(bob, 10_000e18);

    vm.prank(alice);
    locking.lock(alice, alice, 2000e18, 1, 103);

    vm.prank(bob);
    locking.lock(bob, bob, 1500e18, 1, 103);

    vm.timeTravel(BLOCKS_DAY);

    for (uint256 i = 0; i < 45_000; i++) {
      vm.prank(alice);
      locking.lock(alice, bob, 100, 1, 103);
    }
    _;
  }

  function setUp() public {
    vm.roll(21871402); // (Oct-11-2023 WED 12:00:01 PM +UTC)
    vm.warp(1697025601); // (Oct-11-2023 WED 12:00:01 PM +UTC)

    GovernanceFactory.MentoTokenAllocationParams memory allocationParams = GovernanceFactory
      .MentoTokenAllocationParams({
        airgrabAllocation: 50,
        mentoTreasuryAllocation: 100,
        additionalAllocationRecipients: Arrays.addresses(address(mentoLabsMultisig)),
        additionalAllocationAmounts: Arrays.uints(200)
      });

    vm.prank(owner);
    factory = new GovernanceFactory(celoGovernance);

    vm.prank(celoGovernance);
    factory.createGovernance(watchdogMultisig, merkleRoot, fractalSigner, allocationParams);
    proxyAdmin = factory.proxyAdmin();
    mentoToken = factory.mentoToken();
    emission = factory.emission();
    airgrab = factory.airgrab();
    governanceTimelock = factory.governanceTimelock();
    mentoGovernor = factory.mentoGovernor();
    locking = factory.locking();

    // Without this cast, tests do not work as expected
    // It causes a yul exception about memory safety
    governanceTimelockAddress = address(governanceTimelock);

    vm.prank(alice);
    mentoToken.approve(address(locking), type(uint256).max);
    vm.prank(bob);
    mentoToken.approve(address(locking), type(uint256).max);
  }

  function test_queueAndExecute_whenUsedWith10_000Locks_shouldCostReasonableGas() public s_attack {
    address newEmissionTarget = makeAddr("NewEmissionTarget");

    // one more lock in the same block with propose
    vm.prank(alice);
    locking.lock(alice, bob, 100, 1, 103);

    uint256 gasLeftBefore = gasleft();
    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = Proposals._proposeChangeEmissionTarget(mentoGovernor, emission, newEmissionTarget);

    console.log("Gas used for proposal: %d", gasLeftBefore - gasleft());
    assertLt(gasLeftBefore - gasleft(), proposalCreationGas);

    // ~10 mins
    vm.timeTravel(120);

    vm.prank(alice);
    locking.lock(alice, bob, 100, 1, 103);

    // ~10 mins
    vm.timeTravel(120);

    // Locking for bob in the same block with castVote
    vm.prank(alice);
    locking.lock(alice, bob, 100, 1, 103);

    gasLeftBefore = gasleft();

    vm.prank(alice);
    mentoGovernor.castVote(proposalId, 1);
    console.log("Gas used for castVote by alice: %d", gasLeftBefore - gasleft());
    assertLt(gasLeftBefore - gasleft(), voteGas);
    gasLeftBefore = gasleft();

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);
    console.log("Gas used for castVote by bob: %d", gasLeftBefore - gasleft());
    assertLt(gasLeftBefore - gasleft(), voteGas);

    // voting period ends
    vm.timeTravel(BLOCKS_WEEK);

    gasLeftBefore = gasleft();
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));
    console.log("Gas used for queue: %d", gasLeftBefore - gasleft());
    assertLt(gasLeftBefore - gasleft(), proposalQueueGas);

    vm.timeTravel(2 * BLOCKS_DAY);

    gasLeftBefore = gasleft();
    // anyone can execute the proposal after the timelock
    vm.prank(makeAddr("Random"));
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
    console.log("Gas used for execute: %d", gasLeftBefore - gasleft());
    assertLt(gasLeftBefore - gasleft(), proposalExecutionGas);

    // protected function is called by the owner after execution
    assertEq(emission.emissionTarget(), newEmissionTarget);
  }
}
