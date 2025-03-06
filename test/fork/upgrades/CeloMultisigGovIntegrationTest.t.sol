pragma solidity ^0.8;

import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { LockingBase } from "contracts/governance/locking/LockingBase.sol";
import { IGovernor } from "openzeppelin-contracts/contracts/governance/IGovernor.sol";
// solhint-disable-next-line max-line-length
import { GovernorCompatibilityBravoUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/compatibility/GovernorCompatibilityBravoUpgradeable.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

interface ICeloApproversMultisig {
  function submitTransaction(address destination, uint256 value, bytes calldata data) external returns (uint256);
  function executeTransaction(uint256 transactionId) external;
  function confirmTransaction(uint256 transactionId) external;
  function isConfirmed(uint256 transactionId) external view returns (bool);
  function getOwners() external view returns (address[] memory);
  function required() external view returns (uint256);
}

import { ERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/ERC20.sol";

contract CeloMultisigGovIntegrationTest is Test {
  address public governanceFactoryAddress = 0xee6CE2dbe788dFC38b8F583Da86cB9caf2C8cF5A;
  address public celoApprovers = 0x41822d8A191fcfB1cfcA5F7048818aCd8eE933d3;

  GovernanceFactory public governanceFactory = GovernanceFactory(governanceFactoryAddress);
  address payable public mentoGovernor;
  address public governanceTimelock;
  address public mentoToken;
  address public veMento;

  ICeloApproversMultisig public celoApproversMultisig = ICeloApproversMultisig(celoApprovers);

  function setUp() public {
    vm.createSelectFork("https://forno.celo.org");
    mentoGovernor = payable(address(governanceFactory.mentoGovernor()));
    governanceTimelock = address(governanceFactory.governanceTimelock());
    mentoToken = address(governanceFactory.mentoToken());
    veMento = address(governanceFactory.locking());
  }

  function test_approversCanProposeNewProposal() public {
    giveAproversVotingPower();
    uint256 minCliffPeriod = Locking(veMento).minCliffPeriod();
    assertEq(minCliffPeriod, 0);

    vm.roll(block.number + 1);

    address[] memory owners = celoApproversMultisig.getOwners();
    address firstOwner = owners[0];

    address[] memory targets = new address[](1);
    targets[0] = veMento;
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(LockingBase.setMinCliffPeriod.selector, uint32(1));
    string memory description = "Test proposal";

    console.log("Proposing new proposal to governance increasing min cliff period to 1 week");
    console.log("Current: min cliff period", minCliffPeriod);

    console.log("Submitting propose txs to approvers multisig");
    vm.prank(firstOwner);
    uint256 transactionId = ICeloApproversMultisig(celoApprovers).submitTransaction(
      mentoGovernor,
      0,
      abi.encodeWithSelector(IGovernor.propose.selector, targets, values, calldatas, description)
    );

    console.log("Confirming propose txs to approvers multisig");
    uint256 required = celoApproversMultisig.required();
    for (uint256 i = 1; i < required; i++) {
      address approverNext = owners[i];
      vm.prank(approverNext);
      ICeloApproversMultisig(celoApprovers).confirmTransaction(transactionId);
    }

    // uint256 proposalId = uint256(keccak256(abi.encode(targets, values, calldatas, keccak256(bytes(description)))));
    uint256 proposalId = IGovernor(mentoGovernor).hashProposal(
      targets,
      values,
      calldatas,
      keccak256(bytes(description))
    );
    vm.roll(block.number + 1);

    console.log("Proposal state", uint256(IGovernor(mentoGovernor).state(proposalId)), "1 = Active");

    console.log("================================================");

    vm.prank(firstOwner);

    console.log("Submitting vote txs to approvers multisig");

    uint256 castVoteTransactionId = ICeloApproversMultisig(celoApprovers).submitTransaction(
      mentoGovernor,
      0,
      abi.encodeWithSelector(IGovernor.castVote.selector, proposalId, 1)
    );

    console.log("Confirming vote txs to approvers multisig");
    for (uint256 i = 1; i < required; i++) {
      address approverNext = owners[i];
      vm.prank(approverNext);
      ICeloApproversMultisig(celoApprovers).confirmTransaction(castVoteTransactionId);
    }

    vm.roll(block.number + 1);

    console.log("Did Approvers vote: ", IGovernor(mentoGovernor).hasVoted(proposalId, celoApprovers));

    console.log("rolling forward to voting period end");

    vm.roll(block.number + IGovernor(mentoGovernor).votingPeriod());

    console.log("Proposal state", uint256(IGovernor(mentoGovernor).state(proposalId)), "4 = Succeeded");

    console.log("================================================");

    vm.startPrank(firstOwner);

    console.log("Queueing proposal");
    GovernorCompatibilityBravoUpgradeable(mentoGovernor).queue(proposalId);

    vm.roll(block.number + 1);

    console.log("Proposal state", uint256(IGovernor(mentoGovernor).state(proposalId)), "5 = Queued");

    console.log("================================================");

    console.log("Jumping in time past timelock delay");
    vm.warp(block.timestamp + 2 days);

    console.log("Executing proposal");
    GovernorCompatibilityBravoUpgradeable(mentoGovernor).execute(proposalId);

    vm.roll(block.number + 1);

    console.log("Proposal state", uint256(IGovernor(mentoGovernor).state(proposalId)), "7 = Executed");

    vm.stopPrank();

    uint256 minCliffPeriodAfterExecute = Locking(veMento).minCliffPeriod();

    console.log("Min cliff period After execute", minCliffPeriodAfterExecute);
    console.log("================================================");

    assertEq(minCliffPeriodAfterExecute, 1);
  }

  function giveAproversVotingPower() public {
    console.log("================================================");
    console.log("Giving Aprovers 10 mio veMento");

    vm.startPrank(governanceTimelock);
    ERC20(mentoToken).approve(veMento, type(uint256).max);
    Locking(veMento).lock(celoApprovers, celoApprovers, 10_000_000e18, 103, 103);
    vm.stopPrank();

    console.log("Approvers veMento balance scaled", ERC20(veMento).balanceOf(celoApprovers) / 1e18);
    console.log("================================================");
  }
}
