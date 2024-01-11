// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

interface ICeloGovernance {
  struct Transaction {
    uint256 value;
    address destination;
    bytes data;
  }

  function minDeposit() external view returns (uint256);

  function dequeued(uint256 index) external view returns (uint256);

  function execute(uint256 proposalId, uint256 index) external;

  function propose(
    uint256[] calldata values,
    address[] calldata destinations,
    bytes calldata data,
    uint256[] calldata dataLengths,
    string calldata descriptionUrl
  ) external payable returns (uint256);
}
