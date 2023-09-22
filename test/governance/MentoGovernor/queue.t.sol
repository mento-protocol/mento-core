// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length, contract-name-camelcase

import { MentoGovernor_Test } from "./Base.t.sol";

contract Queue_MentoGovernor_Test is MentoGovernor_Test {
  uint256 internal votingDelay;
  uint256 internal votingPeriod;

  uint256 private proposalId;
  address[] private targets;
  uint256[] private values;
  bytes[] private calldatas;
  string private description;

  function _subject() internal {
    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));
  }

  function setUp() public override {
    super.setUp();
    _initMentoGovernor();

    votingDelay = mentoGovernor.votingDelay();
    votingPeriod = mentoGovernor.votingPeriod();

    mockVeMento.mint(alice, mentoGovernor.proposalThreshold());
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.prank(alice);
    (proposalId, targets, values, calldatas, description) = _proposeCallProtectedFunction();
  }

  function test_queue_shouldRevert_whenNotCorrectState() public {
    vm.expectRevert("Governor: proposal not successful");
    _subject();

    vm.roll(block.number + votingDelay + 1);

    vm.expectRevert("Governor: proposal not successful");
    _subject();

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 0);

    vm.expectRevert("Governor: proposal not successful");
    _subject();

    vm.roll(block.number + votingPeriod);

    vm.expectRevert("Governor: proposal not successful");
    _subject();
  }

  function test_queue_shouldRevert_whenNotAuth() public {
    vm.roll(block.number + votingDelay + 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + votingPeriod);

    vm.expectRevert(
      "AccessControl: account 0x5991a2df15a8f6a256d3ec51e99254cd3fb576a9 is missing role 0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1"
    );
    _subject();
  }

  function test_queue_shouldWork() public {
    _setTimelockRoles();

    vm.roll(block.number + votingDelay + 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + votingPeriod);

    _subject();
  }

  function test_queue_shouldRevert_whenRetried() public {
    _setTimelockRoles();

    vm.roll(block.number + votingDelay + 1);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + votingPeriod);

    _subject();

    vm.expectRevert("Governor: proposal not successful");
    _subject();
  }
}
