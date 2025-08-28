// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IAdaptore } from "../interfaces/IAdaptore.sol";
import { IBreakerBox } from "../interfaces/IBreakerBox.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IMarketHoursBreaker } from "../interfaces/IMarketHoursBreaker.sol";

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

contract Adaptore is IAdaptore, Ownable {
  // TODO: Make Ownable upgradeable/initializable
  // Use storage pointer pattern
  // setters and getters for external contracts

  ISortedOracles public sortedOracles;
  IBreakerBox public breakerBox;
  IMarketHoursBreaker public marketHoursBreaker;

  constructor(address _sortedOracles, address _breakerBox, address _marketHoursBreaker) {
    _transferOwnership(msg.sender);

    sortedOracles = ISortedOracles(_sortedOracles);
    breakerBox = IBreakerBox(_breakerBox);
    marketHoursBreaker = IMarketHoursBreaker(_marketHoursBreaker);
  }

  /**
   * @notice Returns true if the market is open
   * @return true if the market is open, false otherwise
   */
  function isMarketOpen() external view returns (bool) {
    return marketHoursBreaker.isMarketOpen(block.timestamp);
  }

  /**
   * @notice Returns the trading mode for a given rate feed ID
   * @param rateFeedID The address of the rate feed
   * @return The trading mode
   */
  function getTradingMode(address rateFeedID) external view returns (uint8) {
    return breakerBox.getRateFeedTradingMode(rateFeedID);
  }

  /**
   * @notice Returns the exchange rate for a given rate feed ID
   * with 18 decimals of precision
   * @param rateFeedID The address of the rate feed
   * @return numerator The numerator of the rate
   * @return denominator The denominator of the rate
   */
  function getRate(address rateFeedID) external view returns (uint256 numerator, uint256 denominator) {
    (numerator, denominator) = sortedOracles.medianRate(rateFeedID);

    numerator = numerator / 1e6;
    denominator = denominator / 1e6;
  }

  /**
   * @notice Returns true if the rate for a given rate feed ID is valid
   * @param rateFeedID The address of the rate feed
   * @return true if the rate is valid, false otherwise
   */
  function hasValidRate(address rateFeedID) external view returns (bool) {
    uint256 reportExpiry = sortedOracles.getTokenReportExpirySeconds(rateFeedID);
    uint256 reportTs = sortedOracles.medianTimestamp(rateFeedID);

    return reportTs > block.timestamp - reportExpiry;
  }
}
