// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;

interface IChainlinkRelayerFactory {
  function initialize(address _sortedOracles) external;

  function sortedOracles() external returns (address);

  function deployRelayer(address rateFeedId, address chainlinkAggregator) external returns (address);

  function removeRelayer(address rateFeedId) external;

  function redeployRelayer(address rateFeedId, address chainlinkAggregator) external returns (address);

  function getRelayer(address rateFeedId) external view returns (address);

  function getRelayers() external view returns (address[] memory);

  function computedRelayerAddress(address rateFeedId, address chainlinkAggregator) external returns (address);
}
