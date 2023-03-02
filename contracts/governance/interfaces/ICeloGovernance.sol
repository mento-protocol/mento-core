// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

interface ICeloGovernance {
  struct Transaction {
    uint256 value;
    address destination;
    bytes data;
  }

  function minDeposit() external returns (uint256);

  function propose(
    uint256[] calldata values,
    address[] calldata destinations,
    bytes calldata data,
    uint256[] calldata dataLengths,
    string calldata descriptionUrl
  ) external payable returns (uint256);
}
