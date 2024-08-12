// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

interface IChainlinkRelayer {
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

  function rateFeedDescription() external returns (string memory);

  function sortedOracles() external returns (address);

  function getAggregators() external returns (ChainlinkAggregator[] memory);

  function maxTimestampSpread() external returns (uint256);

  function relay() external;
}
