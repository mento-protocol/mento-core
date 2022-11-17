// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";

contract GovernanceHelper {
  function serializeTransactions(ICeloGovernance.Transaction[] memory transactions)
    internal
    pure
    returns (
      uint256[] memory values,
      address[] memory destinations,
      bytes memory data,
      uint256[] memory dataLengths
    )
  {
    values = new uint256[](transactions.length);
    destinations = new address[](transactions.length);
    dataLengths = new uint256[](transactions.length);

    for (uint256 i = 0; i < transactions.length; i++) {
      values[i] = transactions[i].value;
      destinations[i] = transactions[i].destination;
      data = abi.encodePacked(data, transactions[i].data);
      dataLengths[i] = transactions[i].data.length;
    }
  }
}
