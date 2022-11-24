// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";

contract GovernanceHelper is Script {
  struct SerializedTransactions {
    uint256[] values;
    address[] destinations;
    bytes data;
    uint256[] dataLengths;
  }

  function createProposal(
    ICeloGovernance.Transaction[] memory transactions, 
    string memory descriptionURL,
    address governance
  ) internal {
    // Serialize transactions
    SerializedTransactions memory serTxs = serializeTransactions(transactions);

    uint256 depositAmount = ICeloGovernance(governance).minDeposit();
    console2.log("Celo governance proposal required deposit amount: ", depositAmount);

    // Submit proposal
    (bool success, bytes memory returnData) = address(governance).call.value(depositAmount)(
      abi.encodeWithSelector(
        ICeloGovernance(0).propose.selector,
        serTxs.values,
        serTxs.destinations,
        serTxs.data,
        serTxs.dataLengths,
        descriptionURL
      )
    );

    if (success == false) {
      console2.log("Failed to create proposal");
      console2.logBytes(returnData);
    }
    require(success);
    console2.log("Proposal was successfully created. ID: ", abi.decode(returnData, (uint256)));
  }

  function simulateProposal(ICeloGovernance.Transaction[] memory transactions, address governance) internal {
    vm.activeFork();
    vm.startPrank(governance);
    for (uint256 i = 0; i < transactions.length; i++) {
      ICeloGovernance.Transaction memory _tx = transactions[i];
      (bool success, bytes memory returnData) = _tx.destination.call.value(_tx.value)(_tx.data);
      if (success == false) {
        console2.log("Failed to simulate the proposal");
        console2.logBytes(returnData);
      }
      require(success);
    }
    console2.log("Proposal was simulated successfully.");
    vm.stopPrank();
  }

  function serializeTransactions(ICeloGovernance.Transaction[] memory transactions)
    internal
    pure
    returns (SerializedTransactions memory serTxs)
  {
    //   uint256[] memory values,
    //   address[] memory destinations,
    //   bytes memory data,
    //   uint256[] memory dataLengths
    // )
    serTxs.values = new uint256[](transactions.length);
    serTxs.destinations = new address[](transactions.length);
    serTxs.dataLengths = new uint256[](transactions.length);

    for (uint256 i = 0; i < transactions.length; i++) {
      serTxs.values[i] = transactions[i].value;
      serTxs.destinations[i] = transactions[i].destination;
      serTxs.data = abi.encodePacked(serTxs.data, transactions[i].data);
      serTxs.dataLengths[i] = transactions[i].data.length;
    }
  }
}
