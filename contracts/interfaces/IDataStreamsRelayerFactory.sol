// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

import { IDataStreamsRelayer } from "./IDataStreamsRelayer.sol";

interface IDataStreamsRelayerFactory {
  /**
   * @notice Emitted when a new DataStreamsRelayerV1 is deployed.
   * @param relayerAddress Address of the newly deployed relayer.
   * @param rateFeedId Rate feed ID for which the relayer will report.
   * @param rateFeedDescription Human-readable rate feed, e.g. "USD/CHF".
   * @param legs List of StreamLeg structs defining the price composition path.
   */
  event RelayerDeployed(
    address indexed relayerAddress,
    address indexed rateFeedId,
    string rateFeedDescription,
    IDataStreamsRelayer.StreamLeg[] legs
  );

  /**
   * @notice Emitted when the relayer deployer is updated.
   * @param newRelayerDeployer Address of the new relayer deployer.
   * @param oldRelayerDeployer Address of the old relayer deployer.
   */
  event RelayerDeployerUpdated(address indexed newRelayerDeployer, address indexed oldRelayerDeployer);

  /**
   * @notice Emitted when a relayer is removed.
   * @param relayerAddress Address of the removed relayer.
   * @param rateFeedId Rate feed ID for which the relayer reported.
   */
  event RelayerRemoved(address indexed relayerAddress, address indexed rateFeedId);

  function initialize(address _sortedOracles, address _verifierProxy, address _relayerDeployer) external;

  function sortedOracles() external view returns (address);

  function verifierProxy() external view returns (address);

  function relayerDeployer() external view returns (address);

  function setRelayerDeployer(address _relayerDeployer) external;

  function deployRelayer(
    address rateFeedId,
    string calldata rateFeedDescription,
    uint256 maxTimestampSpread,
    uint256 maxStaleness,
    IDataStreamsRelayer.StreamLeg[] calldata legs
  ) external returns (address);

  function removeRelayer(address rateFeedId) external;

  function redeployRelayer(
    address rateFeedId,
    string calldata rateFeedDescription,
    uint256 maxTimestampSpread,
    uint256 maxStaleness,
    IDataStreamsRelayer.StreamLeg[] calldata legs
  ) external returns (address);

  function getRelayer(address rateFeedId) external view returns (address);

  function getRelayers() external view returns (address[] memory);

  function computeRelayerAddress(
    address rateFeedId,
    string calldata rateFeedDescription,
    uint256 maxTimestampSpread,
    uint256 maxStaleness,
    IDataStreamsRelayer.StreamLeg[] calldata legs
  ) external view returns (address);

  /**
   * @notice Routes signed reports to the registered relayer for a given rateFeedId.
   * @dev Permissionless. Resolves rateFeedId → relayer → relay(signedReports).
   *      Called as a state-changing pre-step in swap transactions before the view oracle read.
   *      Reverts if no relayer is registered for the rateFeedId.
   * @param rateFeedId The Mento rateFeedId whose relayer should receive the reports.
   * @param signedReports Signed report payloads from the Data Streams API, one per leg in leg order.
   * @param parameterPayload Fee parameter payload forwarded to the VerifierProxy. Empty bytes on Celo.
   */
  function ingest(address rateFeedId, bytes[] calldata signedReports, bytes calldata parameterPayload) external;
}
