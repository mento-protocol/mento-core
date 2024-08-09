// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

interface IChainlinkRelayer {
  /**
   * @notice Configuration of a ChainlinkRelayer. It contains
   * up to 4 chainlink aggregators and their respective inversion
   * settings. For a relayer with N (1<=N<=4) aggregators, only
   * the first N must have a non-zero addresss.
   * @param maxTimestampSpread Maximum spread between aggregator timestamps.
   * @param chainlinkAggregatorN The Nth chainlink aggregator address.
   * @param invertAggregatorN The Nth inversion setting for the price.
   */
  struct Config {
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
   * @notice Struct used to represent a segment in the price path.
   * @member aggregator The address of the Chainink aggregator.
   * @member invert Wether to invert the aggregator.
   */
  struct ChainlinkAggregator {
    address aggregator;
    bool invert;
  }

  function rateFeedId() external returns (address);

  function sortedOracles() external returns (address);

  function getConfig() external returns (Config memory);

  function maxTimestampSpread() external returns (uint256);

  function relay() external;
}
