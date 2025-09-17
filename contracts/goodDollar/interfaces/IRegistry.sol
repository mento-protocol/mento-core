// SPDX-License-Identifier: MIT
pragma solidity >=0.8;

interface IRegistry {
  function initialize() external;

  function transferOwnership(address) external;
}
