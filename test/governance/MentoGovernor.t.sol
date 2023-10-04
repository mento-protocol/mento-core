// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length

import { TestSetup } from "./TestSetup.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";
import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { MockOwnable } from "../mocks/MockOwnable.sol";
import { MockVeMento } from "../mocks/MockVeMento.sol";
import { IVotesUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesUpgradeable.sol";

contract MentoGovernorTest is TestSetup {
  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;

  MockOwnable public mockOwnable;
  MockVeMento public mockVeMento;

  uint256 private _votingDelay;
  uint256 private _votingPeriod;
  uint256 private _threshold;

  function setUp() public {
    vm.startPrank(owner);

    mockVeMento = new MockVeMento();
    mockOwnable = new MockOwnable();

    timelockController = new TimelockController();
    mentoGovernor = new MentoGovernor();

    address[] memory proposers;
    address[] memory executors;

    timelockController.__MentoTimelockController_init(1 days, proposers, executors, owner);
    mentoGovernor.__MentoGovernor_init(IVotesUpgradeable(address(mockVeMento)), timelockController);

    mockOwnable.transferOwnership(address(timelockController));

    bytes32 proposerRole = timelockController.PROPOSER_ROLE();
    bytes32 executorRole = timelockController.EXECUTOR_ROLE();
    bytes32 adminRole = timelockController.TIMELOCK_ADMIN_ROLE();

    timelockController.grantRole(proposerRole, address(mentoGovernor));
    timelockController.grantRole(executorRole, address(0));
    timelockController.revokeRole(adminRole, owner);

    vm.stopPrank();

    _votingDelay = mentoGovernor.votingDelay();
    _votingPeriod = mentoGovernor.votingPeriod();
    _threshold = mentoGovernor.proposalThreshold();
  }

  function test_shouldSetStateCorrectly() public {
    assertEq(mockOwnable.owner(), address(timelockController));
    assertEq(_votingDelay, BLOCKS_DAY);
    assertEq(_votingPeriod, BLOCKS_WEEK);
    assertEq(_threshold, 1_000e18);
    assertEq(timelockController.getMinDelay(), 1 days);
  }

  function test_propose_shouldRevert_whenProposerBelowThreshold() public {
    vm.startPrank(alice);

    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _proposeCallProtectedFunction();

    mockVeMento.mint(alice, _threshold - 1e18);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _proposeCallProtectedFunction();

    mockVeMento.mint(alice, 1e18 - 1);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _proposeCallProtectedFunction();

    vm.stopPrank();
  }

  function test_propose_shouldCreateProposal_whenProposerAboveThreshold() public {
    mockVeMento.mint(alice, _threshold);

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeCallProtectedFunction();

    uint256 hashedParams = _hashProposal(targets, values, calldatas, description);
    assertEq(proposalId, hashedParams);
    assertEq(uint256(mentoGovernor.state(hashedParams)), 0);
  }

  function test_castVote_shouldRevert_whenInVotinDelay() public {
    mockVeMento.mint(alice, _threshold);

    vm.prank(alice);
    (uint256 proposalId, , , , ) = _proposeCallProtectedFunction();

    vm.expectRevert("Governor: vote not currently active");
    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);
  }

  function test_castVote_shouldRevert_when_votingPeriodEnds() public {
    mockVeMento.mint(alice, _threshold);
    vm.prank(alice);
    (uint256 proposalId, , , , ) = _proposeCallProtectedFunction();

    vm.roll(block.number + _votingDelay + _votingPeriod + 1);

    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated

    vm.expectRevert("Governor: vote not currently active");
    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);
  }

  function test_castVote_shouldDefeatProposal_whenNotEnoughForVotes() public {
    mockVeMento.mint(alice, _threshold);
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 1_001e18);

    vm.prank(alice);
    (uint256 proposalId, , , , ) = _proposeCallProtectedFunction();

    vm.roll(block.number + _votingDelay + 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);
    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 0);

    vm.roll(block.number + _votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated
  }

  function test_castVote_shouldDefeatProposal_whenNoQuorum() public {
    mockVeMento.mint(alice, _threshold);
    mockVeMento.mint(bob, 100e18);

    vm.prank(alice);
    (uint256 proposalId, , , , ) = _proposeCallProtectedFunction();

    vm.roll(block.number + _votingDelay + 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated
  }

  function test_castVote_shouldSucceedProposal_whenEnoughQuorumAndVotes() public {
    mockVeMento.mint(alice, _threshold);
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.prank(alice);
    (uint256 proposalId, , , , ) = _proposeCallProtectedFunction();

    vm.roll(block.number + _votingDelay + 1);

    assertEq(uint256(mentoGovernor.state(proposalId)), 1); // active

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);
    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 4); // succeeded
  }

  function test_queueAndExecute_shouldRevert_whenNotCorrectState() public {
    mockVeMento.mint(alice, _threshold);
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeCallProtectedFunction();

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    // keeping block.ts and block.number in sync
    vm.roll(block.number + _votingDelay + 1);
    vm.warp(block.timestamp + 1 days);

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 0);

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    vm.roll(block.number + _votingPeriod);
    vm.warp(block.timestamp + 7 days);

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  function test_execute_shouldRevert_whenTimelocked() public {
    mockVeMento.mint(alice, _threshold);
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeCallProtectedFunction();

    // keeping block.ts and block.number in sync
    vm.roll(block.number + _votingDelay + 1);
    vm.warp(block.timestamp + 1 days);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    vm.warp(block.timestamp + 7 days);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("TimelockController: operation is not ready");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  function test_execute_shouldExecuteProposal_whenTimelockExpires() public {
    mockVeMento.mint(alice, _threshold);
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeCallProtectedFunction();

    // keeping block.ts and block.number in sync
    vm.roll(block.number + _votingDelay + 1);
    vm.warp(block.timestamp + 1 days);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    vm.warp(block.timestamp + 7 days);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.roll(block.number + BLOCKS_DAY);
    vm.warp(block.timestamp + 1 days);

    assertEq(mockOwnable.protected(), 0);

    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    assertEq(mockOwnable.protected(), 1337);
  }

  function test_queueAndexecute_shouldRevert_whenRetried() public {
    mockVeMento.mint(alice, _threshold);
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeCallProtectedFunction();

    // keeping block.ts and block.number in sync
    vm.roll(block.number + _votingDelay + 1);
    vm.warp(block.timestamp + 1 days);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    vm.warp(block.timestamp + 7 days);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.roll(block.number + BLOCKS_DAY);
    vm.warp(block.timestamp + 1 days);

    assertEq(mockOwnable.protected(), 0);

    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("Governor: proposal not successful");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    assertEq(mockOwnable.protected(), 1337);
  }

  function _proposeCallProtectedFunction()
    internal
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    uint256 newProtected = 1337;

    targets = new address[](1);
    targets[0] = address(mockOwnable);

    values = new uint256[](1);
    values[0] = 0;

    calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(mockOwnable.protectedFunction.selector, newProtected);

    description = "Set protected value to 1337";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  function _hashProposal(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
  ) private pure returns (uint256) {
    return uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))));
  }
}
