// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import "../interfaces/IChainlinkAdapter.sol";
import "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

/**
 * @notice The minimal subset of the SortedOracles interface needed by the
 * adapter.
 * @dev SortedOracles is a Solidity 5.17 contract, thus we can't import the
 * interface directly, so we use a minimal hand-copied one.
 */
interface ISortedOraclesMin {
  function report(
    address token,
    uint256 value,
    address lesserKey,
    address greaterKey
  ) external;

  function medianTimestamp(address token) external view returns (uint256);

  function getTokenReportExpirySeconds(address token) external view returns (uint256);
}

/**
 * @title ChainlinkRelayer
 * @notice The ChainlinkRelayer relays rate feed data from a Chainlink price feed to
 * the SortedOracles contract. A separate instance should be deployed for each
 * rate feed.
 * @dev Assumes that it itself is the only reporter for the given SortedOracles
 * feed.
 */
contract ChainlinkRelayer is IChainlinkRelayer {
  /**
   * @notice The number of digits after the decimal point in FixidityLib
   * values, as used by SortedOracles.
   * @dev See contracts/common/FixidityLib.sol
   */
  uint256 public constant FIXIDITY_DECIMALS = 24;
  /// @notice The rateFeedId this adapter relays for.
  address public immutable rateFeedId;
  /// @notice The address of the SortedOracles contract to report to.
  address public immutable sortedOracles;
  /**
   * @notice The address of the Chainlink aggregator this contract fetches
   * data from.
   */
  address public immutable chainlinkAggregator;

  /**
   * @notice Used when a new price's timestamp is not newer than the most recent
   * SortedOracles timestamp.
   */
  error OldTimestamp();
  /**
   * @notice Used when a new price's timestamp would be considered expired by
   * SortedOracles.
   */
  error ExpiredTimestamp();
  /**
   * @notice Used when a negative price is returned by the Chainlink
   * aggregator.
   */
  error NegativePrice();

  /**
   * @notice Initializes the contract and sets immutable parameters.
   * @param _rateFeedId ID of the rate feed this relayer instance relays for.
   * @param _sortedOracles Address of the SortedOracles contract to relay to.
   * @param _chainlinkAggregator Address of the Chainlink price feed to fetch data from.
   */
  constructor(
    address _rateFeedId,
    address _sortedOracles,
    address _chainlinkAggregator
  ) {
    rateFeedId = _rateFeedId;
    sortedOracles = _sortedOracles;
    chainlinkAggregator = _chainlinkAggregator;
  }

  /**
   * @notice Relays data from the configured Chainlink aggregator to
   * SortedOracles.
   * @dev Checks the price is non-negative (Chainlink uses `int256` rather
   * than `uint256`.
   * @dev Converts the price to a Fixidity value, as expected by
   * SortedOracles.
   * @dev Performs checks on the timestamp, will revert if any fails:
   *      - The timestamp should be strictly newer than the most recent
   *      timestamp in SortedOracles.
   *      - The timestamp should not be considered expired by SortedOracles.
   */
  function relay() external {
    ISortedOraclesMin _sortedOracles = ISortedOraclesMin(sortedOracles);
    (, int256 answer, , uint256 timestamp, ) = AggregatorV3Interface(chainlinkAggregator).latestRoundData();

    uint256 lastTimestamp = _sortedOracles.medianTimestamp(rateFeedId);

    if (lastTimestamp > 0) {
      if (timestamp <= lastTimestamp) {
        revert OldTimestamp();
      }

      if (isTimestampExpired(timestamp)) {
        revert ExpiredTimestamp();
      }
    }

    if (answer < 0) {
      revert NegativePrice();
    }

    uint256 report = chainlinkToFixidity(answer);

    ISortedOraclesMin(sortedOracles).report(rateFeedId, report, address(0), address(0));
  }

  /**
   * @notice Checks if a Chainlink answer's timestamp would be expired in
   * SortedOracles.
   * @param timestamp The timestamp returned by the Chainlink aggregator.
   * @return `true` if expired based on SortedOracles expiry parameter.
   */
  function isTimestampExpired(uint256 timestamp) internal view returns (bool) {
    return block.timestamp - timestamp >= ISortedOraclesMin(sortedOracles).getTokenReportExpirySeconds(token);
  }

  /**
   * @notice Converts a Chainlink answer to an unwrapped Fixidity value.
   * @param answer An answer from the Chainlink aggregator.
   * @return The converted Fixidity value (with 24 decimals).
   */
  function chainlinkToFixidity(int256 answer) internal view returns (uint256) {
    uint256 chainlinkDecimals = uint256(AggregatorV3Interface(aggregator).decimals());
    return uint256(answer) * 10**(FIXIDITY_DECIMALS - chainlinkDecimals);
  }
}
