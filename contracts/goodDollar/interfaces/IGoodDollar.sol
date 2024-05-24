// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.18;

interface IGoodDollar {
  function mint(address to, uint256 amount) external returns (bool);
}
