// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;

interface IChainlinkRelayer {
  function rateFeedId() external returns (address);

  function sortedOracles() external returns (address);

  function pricePath() external returns (address[] memory, bool[] memory);

  function maxTimestampSpread() external returns (uint256);

  function relay() external;
}
