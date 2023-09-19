// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length
import { GovernorUpgradeable, IGovernorUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/GovernorUpgradeable.sol";
import { GovernorCompatibilityBravoUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import { GovernorVotesUpgradeable, IVotesUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesUpgradeable.sol";
import { GovernorVotesQuorumFractionUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import { GovernorTimelockControlUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import { TimelockControllerUpgradeable, IERC165Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/TimelockControllerUpgradeable.sol";

contract MentoGovernor is
  GovernorUpgradeable,
  GovernorCompatibilityBravoUpgradeable,
  GovernorVotesUpgradeable,
  GovernorVotesQuorumFractionUpgradeable,
  GovernorTimelockControlUpgradeable
{
  function __MentoGovernor_init(IVotesUpgradeable token_, TimelockControllerUpgradeable timelock_)
    external
    initializer
  {
    __Governor_init("MentoGovernor");
    __GovernorCompatibilityBravo_init();
    __GovernorVotes_init(token_);
    __GovernorVotesQuorumFraction_init(10);
    __GovernorTimelockControl_init(timelock_);
  }

  function votingDelay() public view virtual override returns (uint256) {
    return 0; // TBD
  }

  function votingPeriod() public pure virtual override returns (uint256) {
    return 120960; // TBD: week
  }

  function proposalThreshold() public pure virtual override returns (uint256) {
    return 1337 * 1e18; // TBD
  }

  // The functions below are overrides required by Solidity.
  function quorum(uint256 blockNumber)
    public
    view
    override(IGovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
    returns (uint256)
  {
    return super.quorum(blockNumber);
  }

  function getVotes(address account, uint256 blockNumber)
    public
    view
    override(GovernorUpgradeable, IGovernorUpgradeable)
    returns (uint256)
  {
    return super.getVotes(account, blockNumber);
  }

  function state(uint256 proposalId)
    public
    view
    override(GovernorUpgradeable, IGovernorUpgradeable, GovernorTimelockControlUpgradeable)
    returns (ProposalState)
  {
    return super.state(proposalId);
  }

  function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
  )
    public
    override(GovernorUpgradeable, GovernorCompatibilityBravoUpgradeable, IGovernorUpgradeable)
    returns (uint256)
  {
    return super.propose(targets, values, calldatas, description);
  }

  function _execute(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
    super._execute(proposalId, targets, values, calldatas, descriptionHash);
  }

  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
    return super._cancel(targets, values, calldatas, descriptionHash);
  }

  function _executor()
    internal
    view
    override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
    returns (address)
  {
    return super._executor();
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(GovernorUpgradeable, IERC165Upgradeable, GovernorTimelockControlUpgradeable)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }
}
