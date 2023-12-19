// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length

import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { Emission } from "contracts/governance/Emission.sol";

import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

library Proposals {
  function _proposeChangeEmissionTarget(
    MentoGovernor mentoGovernor,
    Emission emission,
    address newTarget
  )
    internal
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
    calldatas[0] = abi.encodeWithSelector(emission.setEmissionTarget.selector, newTarget);

    description = "Change emission target";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  function _proposeChangeSettings(
    MentoGovernor mentoGovernor,
    TimelockController timelockController,
    Locking locking,
    uint256 votingDelay,
    uint256 votingPeriod,
    uint256 threshold,
    uint256 quorum,
    uint256 minDelay,
    uint32 minCliff,
    uint32 minSlope
  )
    internal
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    targets = new address[](7);
    targets[0] = address(mentoGovernor);
    targets[1] = address(mentoGovernor);
    targets[2] = address(mentoGovernor);
    targets[3] = address(mentoGovernor);
    targets[4] = address(timelockController);
    targets[5] = address(locking);
    targets[6] = address(locking);

    values = new uint256[](7);
    values[0] = 0;
    values[1] = 0;
    values[2] = 0;
    values[3] = 0;
    values[4] = 0;
    values[5] = 0;
    values[6] = 0;

    calldatas = new bytes[](7);
    calldatas[0] = abi.encodeWithSelector(mentoGovernor.setVotingDelay.selector, votingDelay);
    calldatas[1] = abi.encodeWithSelector(mentoGovernor.setVotingPeriod.selector, votingPeriod);
    calldatas[2] = abi.encodeWithSelector(mentoGovernor.setProposalThreshold.selector, threshold);
    calldatas[3] = abi.encodeWithSelector(mentoGovernor.updateQuorumNumerator.selector, quorum);
    calldatas[4] = abi.encodeWithSelector(timelockController.updateDelay.selector, minDelay);
    calldatas[5] = abi.encodeWithSelector(locking.setMinCliffPeriod.selector, minCliff);
    calldatas[6] = abi.encodeWithSelector(locking.setMinSlopePeriod.selector, minSlope);

    description = "Change governance config";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  function _proposeUpgradeContracts(
    MentoGovernor mentoGovernor,
    ProxyAdmin proxyAdmin,
    ITransparentUpgradeableProxy proxy0,
    ITransparentUpgradeableProxy proxy1,
    ITransparentUpgradeableProxy proxy2,
    ITransparentUpgradeableProxy proxy3,
    address newImpl0,
    address newImpl1,
    address newImpl2,
    address newImpl3
  )
    internal
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    targets = new address[](4);
    targets[0] = address(proxyAdmin);
    targets[1] = address(proxyAdmin);
    targets[2] = address(proxyAdmin);
    targets[3] = address(proxyAdmin);

    values = new uint256[](4);
    values[0] = 0;
    values[1] = 0;
    values[2] = 0;
    values[3] = 0;

    calldatas = new bytes[](4);
    calldatas[0] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy0, newImpl0);
    calldatas[1] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy1, newImpl1);
    calldatas[2] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy2, newImpl2);
    calldatas[3] = abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy3, newImpl3);

    description = "Upgrade upgradeable contracts";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }

  function _proposeCancelQueuedTx(
    MentoGovernor mentoGovernor,
    TimelockController mentoLabsTreasury,
    bytes32 id
  )
    internal
    returns (
      uint256 proposalId,
      address[] memory targets,
      uint256[] memory values,
      bytes[] memory calldatas,
      string memory description
    )
  {
    targets = new address[](1);
    targets[0] = address(mentoLabsTreasury);

    values = new uint256[](1);
    values[0] = 0;

    calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(mentoLabsTreasury.cancel.selector, id);

    description = "Cancel queued tx";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }
}
