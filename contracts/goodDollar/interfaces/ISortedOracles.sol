// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.8.19;

interface ISortedOracles {
  function medianRate(address) external view returns (uint256, uint256);

  function numRates(address) external view returns (uint256);
}
