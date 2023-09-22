// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MentoGovernor_Test } from "./Base.t.sol";

contract CastVote_MentoGovernor_Test is MentoGovernor_Test {
  uint256 internal votingDelay;
  uint256 internal votingPeriod;

  uint256 private proposalId;

  function _subject(uint8 support) internal {
    mentoGovernor.castVote(proposalId, support);
  }

  function setUp() public override {
    super.setUp();
    _initMentoGovernor();

    votingDelay = mentoGovernor.votingDelay();
    votingPeriod = mentoGovernor.votingPeriod();

    mockVeMento.mint(alice, mentoGovernor.proposalThreshold());

    vm.prank(alice);
    (proposalId, , , , ) = _proposeCallProtectedFunction();
  }

  function test_castVote_shouldRevert_whenInVotinDelay() public {
    vm.expectRevert("Governor: vote not currently active");
    vm.prank(bob);
    _subject(1);
  }

  function test_castVote_shouldRevert_when_votingPeriodEnds() public {
    vm.roll(block.number + votingDelay + votingPeriod + 1);

    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated

    vm.expectRevert("Governor: vote not currently active");
    vm.prank(bob);
    _subject(1);
  }

  function test_castVote_shouldDefeatProposal_whenNotEnoughForVotes() public {
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 1_001e18);

    vm.roll(block.number + votingDelay + 1);

    vm.prank(bob);
    _subject(1);
    vm.prank(charlie);
    _subject(0);

    vm.roll(block.number + votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated
  }

  function test_castVote_shouldDefeatProposal_whenNoQuorum() public {
    mockVeMento.mint(bob, 100e18);

    vm.roll(block.number + votingDelay + 1);

    vm.prank(bob);
    _subject(1);

    vm.roll(block.number + votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 3); // defeated
  }

  function test_castVote_shouldSucceedProposal_whenEnoughQuorumAndVotes() public {
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.roll(block.number + votingDelay + 1);

    assertEq(uint256(mentoGovernor.state(proposalId)), 1); // active

    vm.prank(bob);
    _subject(0);
    vm.prank(charlie);
    _subject(1);

    vm.roll(block.number + votingPeriod);
    assertEq(uint256(mentoGovernor.state(proposalId)), 4); // succeeded
  }
}
