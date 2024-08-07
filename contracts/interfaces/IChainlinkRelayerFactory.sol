// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

interface IChainlinkRelayerFactory {
  /**
   * @notice Configuration of a ChainlinkRelayer. It contains
   * up to 4 chainlink aggregators and their respective inversion
   * settings. For a relayer with N (1<=N<=4) aggregators, only
   * the first N must have a non-zero addresss.
   * @param maxTimestampSpread maximum spread between aggregator timestamps.
   * @param chainlinkAggregatorN the Nth chainlink aggregator address
   * @param invertAggregatorN the Nth inversion setting for the price
   */
  struct ChainlinkRelayerConfig {
    uint256 maxTimestampSpread;
    address chainlinkAggregator0;
    address chainlinkAggregator1;
    address chainlinkAggregator2;
    address chainlinkAggregator3;
    bool invertAggregator0;
    bool invertAggregator1;
    bool invertAggregator2;
    bool invertAggregator3;
  }

  /**
   * @notice Emitted when a relayer is deployed.
   * @param relayerAddress Address of the newly deployed relayer.
   * @param rateFeedId Rate feed ID for which the relayer will report.
   * @param relayerConfig Chainlink aggregator configuration for the relayer
   */
  event RelayerDeployed(
    address indexed relayerAddress,
    address indexed rateFeedId,
    ChainlinkRelayerConfig relayerConfig
  );

  /**
   * @notice Emitted when a relayer is removed.
   * @param relayerAddress Address of the removed relayer.
   * @param rateFeedId Rate feed ID for which the relayer reported.
   */
  event RelayerRemoved(address indexed relayerAddress, address indexed rateFeedId);

  function initialize(address _sortedOracles) external;

  function sortedOracles() external returns (address);

  function deployRelayer(address rateFeedId, ChainlinkRelayerConfig calldata relayerConfig) external returns (address);

  function removeRelayer(address rateFeedId) external;

  function redeployRelayer(
    address rateFeedId,
    ChainlinkRelayerConfig calldata relayerConfig
  ) external returns (address);

  function getRelayer(address rateFeedId) external view returns (address);

  function getRelayers() external view returns (address[] memory);

  function computedRelayerAddress(
    address rateFeedId,
    ChainlinkRelayerConfig calldata relayerConfig
  ) external returns (address);
}
