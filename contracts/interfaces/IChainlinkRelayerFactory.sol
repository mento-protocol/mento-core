// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

import "./IChainlinkRelayer.sol";

interface IChainlinkRelayerFactory {
  /**
   * @notice Emitted when a relayer is deployed.
   * @param relayerAddress Address of the newly deployed relayer.
   * @param rateFeedId Rate feed ID for which the relayer will report.
   * @param relayerConfig Chainlink aggregator configuration for the relayer
   */
  event RelayerDeployed(
    address indexed relayerAddress,
    address indexed rateFeedId,
    IChainlinkRelayer.Config relayerConfig
  );

  /**
   * @notice Emitted when a relayer is removed.
   * @param relayerAddress Address of the removed relayer.
   * @param rateFeedId Rate feed ID for which the relayer reported.
   */
  event RelayerRemoved(address indexed relayerAddress, address indexed rateFeedId);

  function initialize(address _sortedOracles) external;

  function sortedOracles() external returns (address);

  function deployRelayer(
    address rateFeedId,
    IChainlinkRelayer.Config calldata relayerConfig
  ) external returns (address);

  function removeRelayer(address rateFeedId) external;

  function redeployRelayer(
    address rateFeedId,
    IChainlinkRelayer.Config calldata relayerConfig
  ) external returns (address);

  function getRelayer(address rateFeedId) external view returns (address);

  function getRelayers() external view returns (address[] memory);

  function computedRelayerAddress(
    address rateFeedId,
    IChainlinkRelayer.Config calldata relayerConfig
  ) external returns (address);
}
