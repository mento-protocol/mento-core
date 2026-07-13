// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

/**
 * @notice Interface for a provider-agnostic pull-oracle relayer.
 * @dev Mirrors IChainlinkRelayer in role, but legs are provider feedIds (bytes32) rather than
 *      Chainlink aggregator addresses, and verification is delegated to an IPullOracleAdapter
 *      (Chainlink Data Streams, Pyth, RedStone, ...).
 */
interface IPullOracleRelayer {
  /**
   * @notice A single leg in the price composition path.
   * @custom:member feedId The provider feed identifier (bytes32) for this leg.
   * @custom:member invert Whether to invert this leg's price, e.g. convert USD/JPY to JPY/USD.
   */
  struct OracleLeg {
    bytes32 feedId;
    bool invert;
  }

  /// @notice The Mento rateFeedId this relayer reports for.
  function rateFeedId() external view returns (address);

  /// @notice Human-readable description of the rate feed, e.g. "USD/CHF".
  function rateFeedDescription() external view returns (string memory);

  /// @notice Address of the SortedOracles contract this relayer reports to.
  function sortedOracles() external view returns (address);

  /// @notice The IPullOracleAdapter that verifies update blobs for this relayer's provider.
  function adapter() external view returns (address);

  /// @notice Maximum allowed spread between the oldest and newest leg observationsTimestamp.
  function maxTimestampSpread() external view returns (uint256);

  /// @notice Maximum age of a report's observationsTimestamp relative to block.timestamp.
  function maxStaleness() external view returns (uint256);

  /// @notice The composite observationsTimestamp of the last accepted relay call.
  function lastObservationsTimestamp() external view returns (uint256);

  /// @notice Returns the ordered OracleLeg array defining the price composition path.
  function getLegs() external view returns (OracleLeg[] memory);

  /**
   * @notice Verifies a provider update blob via the adapter and writes the composed rate to
   *         SortedOracles.
   * @dev Permissionless — callable by anyone (swap tx, arbitrageur, dapp, integrator).
   *      Idempotent: re-submitting the same observationsTimestamp is a no-op, not a revert.
   *      Payable: msg.value is forwarded to the adapter to cover provider verification fees
   *      (0 for fee-less providers).
   * @param updateData Provider-specific update blob covering all legs (opaque; see the adapter).
   */
  function relay(bytes calldata updateData) external payable;

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
