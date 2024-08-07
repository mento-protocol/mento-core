// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;

interface IChainlinkRelayerFactory {
  /**
   * @notice Emitted when a relayer is deployed.
   * @param relayerAddress Address of the newly deployed relayer.
   * @param rateFeedId Rate feed ID for which the relayer will report.
   * @param chainlinkAggregator Address of the Chainlink aggregator the relayer will fetch prices from.
   */
  event RelayerDeployed(
    address indexed relayerAddress,
    address indexed rateFeedId,
    address indexed chainlinkAggregator
  );

  /**
   * @notice Emitted when a relayer is removed.
   * @param relayerAddress Address of the removed relayer.
   * @param rateFeedId Rate feed ID for which the relayer reported.
   */
  event RelayerRemoved(address indexed relayerAddress, address indexed rateFeedId);

  function initialize(address _sortedOracles) external;

  function sortedOracles() external returns (address);

  function deployRelayer(address rateFeedId, address chainlinkAggregator) external returns (address);

  function removeRelayer(address rateFeedId) external;

  function redeployRelayer(address rateFeedId, address chainlinkAggregator) external returns (address);

  function getRelayer(address rateFeedId) external view returns (address);

  function getRelayers() external view returns (address[] memory);
}
