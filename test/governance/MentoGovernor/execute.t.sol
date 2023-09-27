// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length, contract-name-camelcase

import { MentoGovernor_Test } from "./Base.t.sol";

contract Execute_MentoGovernor_Test is MentoGovernor_Test {
  uint256 internal votingDelay;
  uint256 internal votingPeriod;

  uint256 private proposalId;
  address[] private targets;
  uint256[] private values;
  bytes[] private calldatas;
  string private description;

  function _subject() internal {
    mentoGovernor.execute(targets, values, calldatas, keccak256(bytes(description)));
  }

  function setUp() public override {
    super.setUp();
    _initMentoGovernor();

    mockOwnable.transferOwnership(address(timelockController));

    votingDelay = mentoGovernor.votingDelay();
    votingPeriod = mentoGovernor.votingPeriod();

    mockVeMento.mint(alice, mentoGovernor.proposalThreshold());
    mockVeMento.mint(bob, 1_000e18);
    mockVeMento.mint(charlie, 2_000e18);

    vm.prank(alice);
    (proposalId, targets, values, calldatas, description) = _proposeCallProtectedFunction();

    // keeping block.ts and block.number in sync
    vm.roll(block.number + votingDelay + 1);
    vm.warp(block.timestamp + 1 days);

    vm.prank(bob);
    mentoGovernor.castVote(proposalId, 1);

    vm.prank(charlie);
    mentoGovernor.castVote(proposalId, 1);

    vm.roll(block.number + votingPeriod);
    vm.warp(block.timestamp + 7 days);
  }

  function test_execute_shouldRevert_whenNotAuth() public {
    vm.expectRevert(
      "AccessControl: account 0x5991a2df15a8f6a256d3ec51e99254cd3fb576a9 is missing role 0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63"
    );
    _subject();
  }

  function test_execute_shouldRevert_whenNotQueued() public {
    _setTimelockRoles();

    vm.expectRevert("TimelockController: operation is not ready");
    _subject();
  }

  function test_execute_shouldRevert_whenTimelocked() public {
    _setTimelockRoles();

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.expectRevert("TimelockController: operation is not ready");
    _subject();
  }

  function test_execute_shouldExecuteProposal_whenTimelockExpires() public {
    _setTimelockRoles();

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.roll(block.number + BLOCKS_DAY);
    vm.warp(block.timestamp + 1 days);

    assertEq(mockOwnable.protected(), 0);

    _subject();

    assertEq(mockOwnable.protected(), 1337);
  }

  function test_queueAndexecute_shouldRevert_whenRetried() public {
    _setTimelockRoles();

    mentoGovernor.queue(targets, values, calldatas, keccak256(bytes(description)));

    vm.roll(block.number + BLOCKS_DAY);
    vm.warp(block.timestamp + 1 days);

    _subject();

    vm.expectRevert("Governor: proposal not successful");
    _subject();
  }
}
