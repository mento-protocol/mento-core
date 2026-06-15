// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

/**
 * @notice Interface for a Chainlink Data Streams pull-oracle relayer.
 * @dev Mirrors IChainlinkRelayer but legs are Data Streams feedIds (bytes32)
 *      rather than Chainlink aggregator addresses.
 */
interface IDataStreamsRelayer {
  /**
   * @notice A single leg in the price composition path.
   * @custom:member feedId The Chainlink Data Streams feedId (bytes32 stream identifier).
   * @custom:member invert Whether to invert this leg's price, e.g. convert USD/JPY to JPY/USD.
   */
  struct StreamLeg {
    bytes32 feedId;
    bool invert;
  }

  /// @notice The Mento rateFeedId this relayer reports for.
  function rateFeedId() external view returns (address);

  /// @notice Human-readable description of the rate feed, e.g. "USD/CHF".
  function rateFeedDescription() external view returns (string memory);

  /// @notice Address of the SortedOracles contract this relayer reports to.
  function sortedOracles() external view returns (address);

  /// @notice Address of the Chainlink Data Streams VerifierProxy.
  function verifierProxy() external view returns (address);

  /// @notice Maximum allowed spread between the oldest and newest leg observationsTimestamp.
  function maxTimestampSpread() external view returns (uint256);

  /// @notice Maximum age of a report's observationsTimestamp relative to block.timestamp.
  function maxStaleness() external view returns (uint256);

  /// @notice The composite observationsTimestamp of the last accepted relay call.
  function lastObservationsTimestamp() external view returns (uint256);

  /// @notice Returns the ordered StreamLeg array defining the price composition path.
  function getLegs() external view returns (StreamLeg[] memory);

  /**
   * @notice Verifies signed Data Streams reports and writes the composed rate to SortedOracles.
   * @dev Permissionless — callable by anyone (swap tx, arbitrageur, dapp, integrator).
   *      Idempotent: re-submitting the same observationsTimestamp is a no-op, not a revert.
   * @param signedReports Signed report payloads from the Data Streams API, one per leg in leg order.
   * @param parameterPayload Fee parameter payload forwarded to the VerifierProxy. Empty bytes on Celo.
   */
  function relay(bytes[] calldata signedReports, bytes calldata parameterPayload) external;

  /**
   * @notice Emitted on a successful relay that writes a new rate to SortedOracles.
   * @param rateFeedId The Mento rateFeedId that was updated.
   * @param rate The composed rate written to SortedOracles (Fixidity scale, 1e24).
   * @param observationsTimestamp The composite (oldest-leg) observationsTimestamp of the reports.
   * @param via The address that submitted the relay call.
   */
  event Relayed(address indexed rateFeedId, uint256 rate, uint256 observationsTimestamp, address indexed via);

  /**
   * @notice Emitted when relay() is called with a report whose observationsTimestamp equals
   *         lastObservationsTimestamp. The call succeeds but no state is written.
   * @param observationsTimestamp The duplicate timestamp that was skipped.
   */
  event ReportSkippedIdempotent(uint256 observationsTimestamp);
}
