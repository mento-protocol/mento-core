// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.8.19;

interface IChainlinkAdapterFactory {
  function sortedOracles() external returns (address);

  function deployRelayer(address rateFeedId, address chainlinkAggregator) external returns (address);

  function getRelayer(address rateFeedId) external view returns (address, uint8);
}
