// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { TestSetup } from "./TestSetup.sol";
import "forge-std/console.sol";

contract MentoGovernorTest is TestSetup {
  uint256 private _votingDelay;
  uint256 private _votingPeriod;
  uint256 private _threshold;

  function setUp() public override {
    super.setUp();
    vm.startPrank(OWNER);

    emission.transferOwnership(address(timelockController));

    bytes32 proposerRole = timelockController.PROPOSER_ROLE();
    bytes32 executorRole = timelockController.EXECUTOR_ROLE();
    bytes32 adminRole = timelockController.TIMELOCK_ADMIN_ROLE();

    timelockController.grantRole(proposerRole, address(mentoGovernor));
    timelockController.grantRole(executorRole, address(0));
    timelockController.revokeRole(adminRole, OWNER);

    vm.stopPrank();

    _votingDelay = mentoGovernor.votingDelay();
    _votingPeriod = mentoGovernor.votingPeriod();
    _threshold = mentoGovernor.proposalThreshold();
  }

  function test_shouldSetStateCorrectly() public {
    assertEq(emission.owner(), address(timelockController));
    assertEq(_votingDelay, BLOCKS_DAY);
    assertEq(_votingPeriod, BLOCKS_WEEK);
    assertEq(_threshold, 1_000e18);
    assertEq(timelockController.getMinDelay(), 1 days);
  }

  function test_propose_shouldRevert_whenProposerBelowThreshold() public {
    vm.startPrank(ALICE);

    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _proposeSetTokenContractOnEmission();

    mockVeMento.mint(ALICE, _threshold - 1e18);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _proposeSetTokenContractOnEmission();

    mockVeMento.mint(ALICE, 1e18 - 1);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _proposeSetTokenContractOnEmission();

    vm.stopPrank();
  }

  function test_propose_shouldCreateProposal_whenProposerAboveThreshold() public {
    mockVeMento.mint(ALICE, _threshold);

    vm.prank(ALICE);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeSetTokenContractOnEmission();

    uint256 hashedParams = _hashProposal(targets, values, calldatas, description);
    assertEq(proposalId, hashedParams);
    assertEq(uint256(mentoGovernor.state(hashedParams)), 0);
  }

  function test_castVote_shouldRevert_whenInVotinDelay() public {
    mockVeMento.mint(ALICE, _threshold);

    vm.prank(ALICE);
    (uint256 proposalId, , , , ) = _proposeSetTokenContractOnEmission();

    vm.expectRevert("Governor: vote not currently active");
    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 1);
  }

  function test_castVote_shouldRevert_when_votingPeriodEnds() public {
    mockVeMento.mint(ALICE, _threshold);
    vm.prank(ALICE);
    (uint256 proposalId, , , , ) = _proposeSetTokenContractOnEmission();

    vm.roll(block.number + _votingDelay + _votingPeriod + 1);

    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated

    vm.expectRevert("Governor: vote not currently active");
    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 1);
  }

  function test_castVote_shouldDefeatProposal_whenNotEnougForVotes() public {
    mockVeMento.mint(ALICE, _threshold);
    mockVeMento.mint(BOB, 1_000e18);
    mockVeMento.mint(CHARLIE, 1_001e18);

    vm.prank(ALICE);
    (uint256 proposalId, , , , ) = _proposeSetTokenContractOnEmission();

    vm.roll(block.number + _votingDelay + 1);

    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 1);
    vm.prank(CHARLIE);
    mentoGovernor.castVote(proposalId, 0);

    vm.roll(block.number + _votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated
  }

  function test_castVote_shouldDefatProposal_whenNoQuorum() public {
    mockVeMento.mint(ALICE, _threshold);
    mockVeMento.mint(BOB, 100e18);

    vm.prank(ALICE);
    (uint256 proposalId, , , , ) = _proposeSetTokenContractOnEmission();

    vm.roll(block.number + _votingDelay + 1);

    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated
  }

  function test_castVote_shouldSucceedProposoal_whenEnoughQuorumAndVotes() public {
    mockVeMento.mint(ALICE, _threshold);
    mockVeMento.mint(BOB, 1_000e18);
    mockVeMento.mint(CHARLIE, 2_000e18);

    vm.prank(ALICE);
    (uint256 proposalId, , , , ) = _proposeSetTokenContractOnEmission();

    vm.roll(block.number + _votingDelay + 1);

    assertEq(uint256(mentoGovernor.state(proposalId)), 1); // active

    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 0);
    vm.prank(CHARLIE);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 4); // succeeded
  }

  function test_queueAndExecute_shouldRevert_whenNotCorrectState() public {
    mockVeMento.mint(ALICE, _threshold);
    mockVeMento.mint(BOB, 1_000e18);
    mockVeMento.mint(CHARLIE, 2_000e18);

    vm.prank(ALICE);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeSetTokenContractOnEmission();

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

    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(CHARLIE);
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
    mockVeMento.mint(ALICE, _threshold);
    mockVeMento.mint(BOB, 1_000e18);
    mockVeMento.mint(CHARLIE, 2_000e18);

    vm.prank(ALICE);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeSetTokenContractOnEmission();

    // keeping block.ts and block.number in sync
    vm.roll(block.number + _votingDelay + 1);
    vm.warp(block.timestamp + 1 days);

    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(CHARLIE);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    vm.warp(block.timestamp + 7 days);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("TimelockController: operation is not ready");
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  function test_execute_shouldExecuteProposal_whenTimelockExpires() public {
    mockVeMento.mint(ALICE, _threshold);
    mockVeMento.mint(BOB, 1_000e18);
    mockVeMento.mint(CHARLIE, 2_000e18);

    vm.prank(ALICE);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _proposeSetTokenContractOnEmission();

    // keeping block.ts and block.number in sync
    vm.roll(block.number + _votingDelay + 1);
    vm.warp(block.timestamp + 1 days);

    vm.prank(BOB);
    mentoGovernor.castVote(proposalId, 0);

    vm.prank(CHARLIE);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + _votingPeriod);
    vm.warp(block.timestamp + 7 days);

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.roll(block.number + _votingDelay);
    vm.warp(block.timestamp + 1 days);

    assertEq(address(emission.mentoToken()), address(0));

    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));

    assertEq(address(emission.mentoToken()), address(mentoToken));
  }

  function _proposeSetTokenContractOnEmission()
    private
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    targets = new address[](1);
    targets[0] = address(emission);

    values = new uint256[](1);
    values[0] = 0;

    calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(emission.setTokenContract.selector, address(mentoToken));

    description = "Set mento token address for emission contract";

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
