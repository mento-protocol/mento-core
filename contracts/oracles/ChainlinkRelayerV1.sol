// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "../interfaces/IChainlinkRelayer.sol";
import "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import { UD60x18, ud, intoUint256 } from "@prb/math/src/UD60x18.sol";

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
 * @dev Assumes that it itself is the only reporter 3or the given SortedOracles
 * feed.
 */
contract ChainlinkRelayerV1 is IChainlinkRelayer {
  /**
   * @notice The number of digits after the decimal point in FixidityLib values, as used by SortedOracles.
   * @dev See contracts/common/FixidityLib.sol
   */
  uint256 public constant FIXIDITY_DECIMALS = 24;

  /// @notice The rateFeedId this relayer relays for.
  address public immutable rateFeedId;

  /// @notice The address of the SortedOracles contract to report to.
  address public immutable sortedOracles;
  /**
   * @notice The addresses and invert settings of the Chainlink aggregator this
   * contract fetches data from, it's limited to 4 potential path segments,
   * because we can't have dynamic types as immutable, and it's not worth the gas
   * to do it this way.
   */
  address public immutable chainlinkAggregator0;
  address public immutable chainlinkAggregator1;
  address public immutable chainlinkAggregator2;
  address public immutable chainlinkAggregator3;
  bool public immutable invertAggregator0;
  bool public immutable invertAggregator1;
  bool public immutable invertAggregator2;
  bool public immutable invertAggregator3;
  /**
   * @notice Maximum deviation allowed between all prices pulled
   * from the chainlink aggregators.
   */
  uint256 public immutable maxTimestampSpread;

  /// @notice Used when a new price's timestamp is not newer than the most recent SortedOracles timestamp.
  error TimestampNotNew();

  /// @notice Used when a new price's timestamp would be considered expired by SortedOracles.
  error ExpiredTimestamp();

  /// @notice Used when a negative price is returned by the Chainlink aggregator.
  error NegativePrice();
  /**
   * @notice Used when a zero price is returned by the Chainlink
   * aggregator.
   */
  error ZeroPrice();
  /**
   * @notice Used when the spread between the earliers and latest timestamp
   * of the aggregators is above the maximum allowed.
   */
  error TimestampSpreadTooHigh();
  /**
   * @notice Used in the constructor when there's an address(0) chainlink
   * aggregator followed by one with a set address, resulting in a gap.
   */
  error PricePathHasGaps();

  /**
   * @notice Initializes the contract and sets immutable parameters.
   * @param _rateFeedId ID of the rate feed this relayer instance relays for.
   * @param _sortedOracles Address of the SortedOracles contract to relay to.
   * @param _chainlinkAggregator0 Addresses of the Chainlink price feeds to fetch data from.
   * @param _chainlinkAggregator1 Addresses of the Chainlink price feeds to fetch data from.
   * @param _chainlinkAggregator2 Addresses of the Chainlink price feeds to fetch data from.
   * @param _chainlinkAggregator3 Addresses of the Chainlink price feeds to fetch data from.
   * @param _invertAggregator0 Bools of wether to invert Aggregators.
   * @param _invertAggregator1 Bools of wether to invert Aggregators.
   * @param _invertAggregator2 Bools of wether to invert Aggregators.
   * @param _invertAggregator3 Bools of wether to invert Aggregators.
   */
  constructor(
    address _rateFeedId,
    address _sortedOracles,
    uint256 _maxTimestampSpread,
    address _chainlinkAggregator0,
    address _chainlinkAggregator1,
    address _chainlinkAggregator2,
    address _chainlinkAggregator3,
    bool _invertAggregator0,
    bool _invertAggregator1,
    bool _invertAggregator2,
    bool _invertAggregator3
  ) {
    if (
      !((_chainlinkAggregator0 != address(0) &&
        _chainlinkAggregator1 == address(0) &&
        _chainlinkAggregator2 == address(0) &&
        _chainlinkAggregator3 == address(0)) ||
        (_chainlinkAggregator0 != address(0) &&
          _chainlinkAggregator1 != address(0) &&
          _chainlinkAggregator2 == address(0) &&
          _chainlinkAggregator3 == address(0)) ||
        (_chainlinkAggregator0 != address(0) &&
          _chainlinkAggregator1 != address(0) &&
          _chainlinkAggregator2 != address(0) &&
          _chainlinkAggregator3 == address(0)) ||
        (_chainlinkAggregator0 != address(0) &&
          _chainlinkAggregator1 != address(0) &&
          _chainlinkAggregator2 != address(0) &&
          _chainlinkAggregator3 != address(0)))
    ) {
      revert PricePathHasGaps();
    }

    rateFeedId = _rateFeedId;
    sortedOracles = _sortedOracles;
    maxTimestampSpread = _maxTimestampSpread;
    chainlinkAggregator0 = _chainlinkAggregator0;
    chainlinkAggregator1 = _chainlinkAggregator1;
    chainlinkAggregator2 = _chainlinkAggregator2;
    chainlinkAggregator3 = _chainlinkAggregator3;
    invertAggregator0 = _invertAggregator0;
    invertAggregator1 = _invertAggregator1;
    invertAggregator2 = _invertAggregator2;
    invertAggregator3 = _invertAggregator3;
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
    (UD60x18 report, uint256 minTimestamp, uint256 maxTimestamp) = getFirstReport();

    if (chainlinkAggregator1 != address(0)) {
      (report, minTimestamp, maxTimestamp) = addPriceToReport(
        report,
        minTimestamp,
        maxTimestamp,
        chainlinkAggregator1,
        invertAggregator1
      );
    }
    if (chainlinkAggregator2 != address(0)) {
      (report, minTimestamp, maxTimestamp) = addPriceToReport(
        report,
        minTimestamp,
        maxTimestamp,
        chainlinkAggregator2,
        invertAggregator2
      );
    }
    if (chainlinkAggregator3 != address(0)) {
      (report, minTimestamp, maxTimestamp) = addPriceToReport(
        report,
        minTimestamp,
        maxTimestamp,
        chainlinkAggregator3,
        invertAggregator3
      );
    }

    if (maxTimestamp - minTimestamp > maxTimestampSpread) {
      revert TimestampSpreadTooHigh();
    }

    uint256 lastTimestamp = _sortedOracles.medianTimestamp(rateFeedId);

    if (lastTimestamp > 0 && maxTimestamp <= lastTimestamp) {
      revert TimestampNotNew();
    }

    if (isTimestampExpired(maxTimestamp)) {
      revert ExpiredTimestamp();
    }

    uint256 reportValue = intoUint256(report) * 10 ** 6; // 18 -> 24 decimals fixidity

    // This contract is built for a setup where it is the only reporter for the
    // given `rateFeedId`. As such, we don't need to compute and provide
    // `lesserKey`/`greaterKey` each time, the "null pointer" `address(0)` will
    // correctly place the report in SortedOracles' sorted linked list.
    ISortedOraclesMin(sortedOracles).report(rateFeedId, reportValue, address(0), address(0));
  }

  function getFirstReport() internal view returns (UD60x18, uint256, uint256) {
    (, int256 _price, , uint256 _timestamp, ) = AggregatorV3Interface(chainlinkAggregator0).latestRoundData();
    if (_price < 0) {
      revert NegativePrice();
    }
    if (_price == 0) {
      revert ZeroPrice();
    }
    UD60x18 report = chainlinkToUD60x18(_price, chainlinkAggregator0);
    if (invertAggregator0) {
      report = ud(1e18).div(report);
    }
    return (report, _timestamp, _timestamp);
  }

  function addPriceToReport(
    UD60x18 report,
    uint256 minTimestamp,
    uint256 maxTimestamp,
    address aggregator,
    bool invert
  ) internal view returns (UD60x18, uint256, uint256) {
    (, int256 _price, , uint256 timestamp, ) = AggregatorV3Interface(aggregator).latestRoundData();
    if (_price < 0) {
      revert NegativePrice();
    }
    if (_price == 0) {
      revert ZeroPrice();
    }
    UD60x18 price = chainlinkToUD60x18(_price, chainlinkAggregator0);
    if (invert) {
      price = ud(1e18).div(price);
    }
    return (
      report.mul(price),
      timestamp < minTimestamp ? timestamp : minTimestamp,
      timestamp > maxTimestamp ? timestamp : maxTimestamp
    );
  }

  function pricePath() public view returns (address[] memory aggregators, bool[] memory toInvert) {
    if (chainlinkAggregator3 != address(0)) {
      aggregators = new address[](4);
      toInvert = new bool[](4);
    } else if (chainlinkAggregator2 != address(0)) {
      aggregators = new address[](3);
      toInvert = new bool[](3);
    } else if (chainlinkAggregator1 != address(0)) {
      aggregators = new address[](2);
      toInvert = new bool[](2);
    } else {
      aggregators = new address[](1);
      toInvert = new bool[](1);
    }
    aggregators[0] = chainlinkAggregator0;
    toInvert[0] = invertAggregator0;
    if (aggregators.length > 1) {
      aggregators[1] = chainlinkAggregator1;
      toInvert[1] = invertAggregator1;
    }
    if (aggregators.length > 2) {
      aggregators[2] = chainlinkAggregator2;
      toInvert[2] = invertAggregator2;
    }
    if (aggregators.length > 3) {
      aggregators[3] = chainlinkAggregator3;
      toInvert[3] = invertAggregator3;
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
   * @notice Converts a Chainlink price to an unwrapped Fixidity value.
   * @param price An price from the Chainlink aggregator.
   * @return The converted UD60x18 value.
   */
  function chainlinkToUD60x18(int256 price, address aggregator) internal view returns (UD60x18) {
    uint256 chainlinkDecimals = uint256(AggregatorV3Interface(aggregator).decimals());
    return ud(uint256(price) * 10 ** (18 - chainlinkDecimals));
  }
}
