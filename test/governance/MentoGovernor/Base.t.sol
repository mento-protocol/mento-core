// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length, func-name-mixedcase, contract-name-camelcase

import { TestSetup } from "../TestSetup.sol";
import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { TimelockController } from "contracts/governance/TimeLockController.sol";
import { MockOwnable } from "../../mocks/MockOwnable.sol";
import { MockVeMento } from "../../mocks/MockVeMento.sol";
import { IVotesUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesUpgradeable.sol";

contract MentoGovernor_Test is TestSetup {
  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;

  MockOwnable public mockOwnable;
  MockVeMento public mockVeMento;

  function _newGovernance() internal {
    timelockController = new TimelockController();
    mentoGovernor = new MentoGovernor();
  }

  function _initMentoGovernor() internal {
    _newGovernance();

    address[] memory proposers;
    address[] memory executors;

    timelockController.__MentoTimelockController_init(1 days, proposers, executors, owner);
    mentoGovernor.__MentoGovernor_init(IVotesUpgradeable(address(mockVeMento)), timelockController);
  }

  function setUp() public virtual {
    mockVeMento = new MockVeMento();
    mockOwnable = new MockOwnable();
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
  ) internal pure returns (uint256) {
    return uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))));
  }

  function _setTimelockRoles() internal {
    bytes32 proposerRole = timelockController.PROPOSER_ROLE();
    bytes32 executorRole = timelockController.EXECUTOR_ROLE();
    bytes32 adminRole = timelockController.TIMELOCK_ADMIN_ROLE();

    vm.startPrank(owner);
    timelockController.grantRole(proposerRole, address(mentoGovernor));
    timelockController.grantRole(executorRole, address(0));
    timelockController.revokeRole(adminRole, owner);
    vm.stopPrank();
  }
}
