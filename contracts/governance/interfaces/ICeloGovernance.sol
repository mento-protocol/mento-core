pragma solidity ^0.5.13;

interface ICeloGovernance {
  struct Transaction {
    uint256 value;
    address destination;
    bytes data;
  }

  function minDeposit() external returns (uint256);
}
