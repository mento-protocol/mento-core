// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length

import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { Emission } from "contracts/governance/Emission.sol";

import { uints, addresses, bytesList } from "mento-std/Array.sol";

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
    targets = addresses(address(emission));
    values = uints(0);
    calldatas = bytesList(abi.encodeWithSelector(emission.setEmissionTarget.selector, newTarget));
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
    targets = addresses(
      address(mentoGovernor),
      address(mentoGovernor),
      address(mentoGovernor),
      address(mentoGovernor),
      address(timelockController),
      address(locking),
      address(locking)
    );
    values = uints(0, 0, 0, 0, 0, 0, 0);
    calldatas = bytesList(
      abi.encodeWithSelector(mentoGovernor.setVotingDelay.selector, votingDelay),
      abi.encodeWithSelector(mentoGovernor.setVotingPeriod.selector, votingPeriod),
      abi.encodeWithSelector(mentoGovernor.setProposalThreshold.selector, threshold),
      abi.encodeWithSelector(mentoGovernor.updateQuorumNumerator.selector, quorum),
      abi.encodeWithSelector(timelockController.updateDelay.selector, minDelay),
      abi.encodeWithSelector(locking.setMinCliffPeriod.selector, minCliff),
      abi.encodeWithSelector(locking.setMinSlopePeriod.selector, minSlope)
    );
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
    targets = addresses(address(proxyAdmin), address(proxyAdmin), address(proxyAdmin), address(proxyAdmin));
    values = uints(0, 0, 0, 0);
    calldatas = bytesList(
      abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy0, newImpl0),
      abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy1, newImpl1),
      abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy2, newImpl2),
      abi.encodeWithSelector(proxyAdmin.upgrade.selector, proxy3, newImpl3)
    );
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
    targets = addresses(address(mentoLabsTreasury));
    values = uints(0);
    calldatas = bytesList(abi.encodeWithSelector(mentoLabsTreasury.cancel.selector, id));
    description = "Cancel queued tx";

    proposalId = mentoGovernor.propose(targets, values, calldatas, description);
  }
}
