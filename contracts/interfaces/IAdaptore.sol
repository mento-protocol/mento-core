// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IBreakerBox } from "./IBreakerBox.sol";
import { ISortedOracles } from "./ISortedOracles.sol";
import { IMarketHoursBreaker } from "./IMarketHoursBreaker.sol";

interface IAdaptore {
  function sortedOracles() external view returns (ISortedOracles);

  function breakerBox() external view returns (IBreakerBox);

  function marketHoursBreaker() external view returns (IMarketHoursBreaker);

  function isMarketOpen() external view returns (bool);

  function hasValidRate(address rateFeedID) external view returns (bool);

  function getRate(address rateFeedID) external view returns (uint256, uint256);

  function getTradingMode(address rateFeedID) external view returns (uint8);
}
