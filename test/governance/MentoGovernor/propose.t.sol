// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
import { MentoGovernor_Test } from "./Base.t.sol";

contract Propose_MentoGovernor_Test is MentoGovernor_Test {
  uint256 internal threshold;

  function _subject()
    internal
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    return _proposeCallProtectedFunction();
  }

  function setUp() public override {
    super.setUp();
    _initMentoGovernor();

    threshold = mentoGovernor.proposalThreshold();
  }

  function test_propose_shouldRevert_whenProposerBelowThreshold() public {
    vm.startPrank(alice);

    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _subject();

    mockVeMento.mint(alice, threshold - 1e18);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _subject();

    mockVeMento.mint(alice, 1e18 - 1);
    vm.expectRevert("Governor: proposer votes below proposal threshold");
    _subject();

    vm.stopPrank();
  }

  function test_propose_shouldCreateProposal_whenProposerAboveThreshold() public {
    mockVeMento.mint(alice, threshold);

    vm.prank(alice);
    (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    ) = _subject();

    uint256 hashedParams = _hashProposal(targets, values, calldatas, description);

    assertEq(proposalId, hashedParams);
    assertEq(uint256(mentoGovernor.state(hashedParams)), 0);
  }
}
