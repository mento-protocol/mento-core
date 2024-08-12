// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "../interfaces/IChainlinkRelayer.sol";
import "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import { UD60x18, ud, intoUint256 } from "prb/math/UD60x18.sol";

/**
 * @notice The minimal subset of the SortedOracles interface needed by the
 * relayer.
 * @dev SortedOracles is a Solidity 5.13 contract, thus we can't import the
 * interface directly, so we use a minimal hand-copied one.
 * See https://github.com/mento-protocol/mento-core/blob/develop/contracts/common/SortedOracles.sol
 */
interface ISortedOraclesMin {
  function report(address rateFeedId, uint256 value, address lesserKey, address greaterKey) external;

  function medianTimestamp(address rateFeedId) external view returns (uint256);

  function getTokenReportExpirySeconds(address rateFeedId) external view returns (uint256);
}

/**
 * @title ChainlinkRelayer
 * @notice The ChainlinkRelayer relays rate feed data from a Chainlink price feed to
 * the SortedOracles contract. A separate instance should be deployed for each
 * rate feed.
 * @dev Assumes that it itself is the only reporter for the given SortedOracles
 * feed.
 */
contract ChainlinkRelayerV1 is IChainlinkRelayer {
  /**
   * @notice The number of digits after the decimal point in FixidityLib values, as used by SortedOracles.
   * @dev See contracts/common/FixidityLib.sol
   */
  uint256 public constant UD60X18_TO_FIXIDITY_SCALE = 1e6; // 10 ** (24 - 18)

  /// @notice The rateFeedId this relayer relays for.
  address public immutable rateFeedId;

  /// @notice The address of the SortedOracles contract to report to.
  address public immutable sortedOracles;
  /**
   * @notice The addresses and invert settings of the Chainlink aggregators this
   * contract fetches data from, it's limited to a maximum of 4 aggregators,
   * because we can't have dynamic types as immutable, and it's not worth the gas
   * to store these as arrays in storage.
   * The values are reconstructed into an array of ChainlinkAggregator structs
   * in the getAggregatorsArray() function
   */
  address public immutable aggregator0Aggregator;
  address public immutable aggregator1Aggregator;
  address public immutable aggregator2Aggregator;
  address public immutable aggregator3Aggregator;
  bool public immutable aggregator0Invert;
  bool public immutable aggregator1Invert;
  bool public immutable aggregator2Invert;
  bool public immutable aggregator3Invert;
  uint256 public immutable aggregatorsCount;
  /**
   * @notice Maximum timestamp deviation allowed between all prices pulled
   * from the Chainlink aggregators.
   */
  uint256 public immutable maxTimestampSpread;
  /// @notice Human readable description of the rate feed, used offchain
  string public rateFeedDescription;

  /// @notice Used when an empty array of aggregators is passed into the constructor.
  error NoAggregators();

  /// @notice Used when a new price's timestamp is not newer than the most recent SortedOracles timestamp.
  error TimestampNotNew();

  /// @notice Used when a new price's timestamp would be considered expired by SortedOracles.
  error ExpiredTimestamp();

  /// @notice Used when a negative or zero price is returned by the Chainlink aggregator.
  error InvalidPrice();
  /**
   * @notice Used when the spread between the earliest and latest timestamp
   * of the aggregators is above the maximum allowed.
   */
  error TimestampSpreadTooHigh();
  /**
   * @notice Used in the constructor when a ChainlinkAggregator
   * has address(0) for an aggregator.
   */
  error InvalidAggregator();

  /**
   * @notice Initializes the contract and sets immutable parameters.
   * @param _rateFeedId ID of the rate feed this relayer instance relays for.
   * @param _rateFeedDescription The human readable description of the reported rate feed.
   * @param _sortedOracles Address of the SortedOracles contract to relay to.
   * @param _maxTimestampSpread Max difference in milliseconds between the earliest and
   *        latest timestamp of all aggregators in the price path.
   * @param _aggregators Array of ChainlinkAggregator structs defining the price path.
   */
  constructor(
    address _rateFeedId,
    string memory _rateFeedDescription,
    address _sortedOracles,
    uint256 _maxTimestampSpread,
    ChainlinkAggregator[] memory _aggregators
  ) {
    rateFeedId = _rateFeedId;
    sortedOracles = _sortedOracles;
    maxTimestampSpread = _maxTimestampSpread;
    rateFeedDescription = _rateFeedDescription;

    aggregatorsCount = _aggregators.length;
    if (aggregatorsCount == 0) {
      revert NoAggregators();
    }

    ChainlinkAggregator[] memory aggregators = new ChainlinkAggregator[](4);
    for (uint256 i = 0; i < _aggregators.length; i++) {
      aggregators[i] = _aggregators[i];
      if (_aggregators[i].aggregator == address(0)) {
        revert InvalidAggregator();
      }
    }

    aggregator0Aggregator = aggregators[0].aggregator;
    aggregator1Aggregator = aggregators[1].aggregator;
    aggregator2Aggregator = aggregators[2].aggregator;
    aggregator3Aggregator = aggregators[3].aggregator;
    aggregator0Invert = aggregators[0].invert;
    aggregator1Invert = aggregators[1].invert;
    aggregator2Invert = aggregators[2].invert;
    aggregator3Invert = aggregators[3].invert;
  }

  /**
   * @notice Get the Chainlink aggregators and their invert settings.
   * @return An array of ChainlinkAggregator that compose the price path.
   */
  function getAggregators() public view returns (ChainlinkAggregator[] memory) {
    return getAggregatorsArray();
  }

  /**
   * @notice Relays data from the configured Chainlink aggregator to SortedOracles.
   * @dev Checks the price is non-negative (Chainlink uses `int256` rather than `uint256`.
   * @dev Converts the price to a Fixidity value, as expected by SortedOracles.
   * @dev Performs checks on the timestamp, will revert if any fails:
   *      - The timestamp should be strictly newer than the most recent timestamp in SortedOracles.
   *      - The timestamp should not be considered expired by SortedOracles.
   */
  function relay() external {
    ISortedOraclesMin _sortedOracles = ISortedOraclesMin(sortedOracles);
    ChainlinkAggregator[] memory aggregators = getAggregatorsArray();

    (UD60x18 report, uint256 timestamp) = readChainlinkAggregator(aggregators[0]);
    uint256 oldestChainlinkTs = timestamp;
    uint256 newestChainlinkTs = timestamp;

    UD60x18 nextReport;
    for (uint256 i = 1; i < aggregators.length; i++) {
      (nextReport, timestamp) = readChainlinkAggregator(aggregators[i]);
      report = report.mul(nextReport);
      oldestChainlinkTs = timestamp < oldestChainlinkTs ? timestamp : oldestChainlinkTs;
      newestChainlinkTs = timestamp > newestChainlinkTs ? timestamp : newestChainlinkTs;
    }

    if (newestChainlinkTs - oldestChainlinkTs > maxTimestampSpread) {
      revert TimestampSpreadTooHigh();
    }

    uint256 lastReportTs = _sortedOracles.medianTimestamp(rateFeedId);

    if (lastReportTs > 0 && newestChainlinkTs <= lastReportTs) {
      revert TimestampNotNew();
    }

    if (isTimestampExpired(newestChainlinkTs)) {
      revert ExpiredTimestamp();
    }

    uint256 reportValue = intoUint256(report) * UD60X18_TO_FIXIDITY_SCALE;

    // This contract is built for a setup where it is the only reporter for the
    // given `rateFeedId`. As such, we don't need to compute and provide
    // `lesserKey`/`greaterKey` each time, the "null pointer" `address(0)` will
    // correctly place the report in SortedOracles' sorted linked list.
    ISortedOraclesMin(sortedOracles).report(rateFeedId, reportValue, address(0), address(0));
  }

  /**
   * @notice Read and validate a Chainlink report from an aggregator.
   * It inverts the value if necessary.
   * @return price UD60x18 report value.
   * @return timestamp uint256 timestamp of the report.
   */
  function readChainlinkAggregator(ChainlinkAggregator memory aggCfg) internal view returns (UD60x18, uint256) {
    (, int256 _price, , uint256 timestamp, ) = AggregatorV3Interface(aggCfg.aggregator).latestRoundData();
    if (_price <= 0) {
      revert InvalidPrice();
    }
    UD60x18 price = chainlinkToUD60x18(_price, aggCfg.aggregator);
    if (aggCfg.invert) {
      price = price.inv();
    }
    return (price, timestamp);
  }

  /**
   * @notice Compose immutable variables into an in-memory array for better handling
   * @return aggregators An array of structs for each aggregator in the price path
   */
  function getAggregatorsArray() internal view returns (ChainlinkAggregator[] memory aggregators) {
    aggregators = new ChainlinkAggregator[](aggregatorsCount);
    unchecked {
      aggregators[0] = ChainlinkAggregator(aggregator0Aggregator, aggregator0Invert);
      if (aggregatorsCount > 1) {
        aggregators[1] = ChainlinkAggregator(aggregator1Aggregator, aggregator1Invert);
        if (aggregatorsCount > 2) {
          aggregators[2] = ChainlinkAggregator(aggregator2Aggregator, aggregator2Invert);
          if (aggregatorsCount > 3) {
            aggregators[3] = ChainlinkAggregator(aggregator3Aggregator, aggregator3Invert);
          }
        }
      }
    }
  }

  /**
   * @notice Checks if a Chainlink price's timestamp would be expired in SortedOracles.
   * @param timestamp The timestamp returned by the Chainlink aggregator.
   * @return `true` if expired based on SortedOracles expiry parameter.
   */
  function isTimestampExpired(uint256 timestamp) internal view returns (bool) {
    return block.timestamp - timestamp >= ISortedOraclesMin(sortedOracles).getTokenReportExpirySeconds(rateFeedId);
  }

  /**
   * @notice Converts a Chainlink price to a UD60x18 value.
   * @param price An price from the Chainlink aggregator.
   * @return The converted UD60x18 value.
   */
  function chainlinkToUD60x18(int256 price, address aggregator) internal view returns (UD60x18) {
    uint256 chainlinkDecimals = uint256(AggregatorV3Interface(aggregator).decimals());
    return ud(uint256(price) * 10 ** (18 - chainlinkDecimals));
  }
}
