// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IBreakerBox } from "./IBreakerBox.sol";
import { ISortedOracles } from "./ISortedOracles.sol";
import { IMarketHoursBreaker } from "./IMarketHoursBreaker.sol";

interface IAdaptore {
  /* ========== STRUCTS ========== */

  /// @notice Struct to store Adaptore contract state
  /// @custom:storage-location erc7201:mento.storage.Adaptore
  struct AdaptoreStorage {
    // Contract for querying oracle price feeds
    ISortedOracles sortedOracles;
    // Contract for checking and managing trading modes
    IBreakerBox breakerBox;
    // Contract for checking and managing market hours
    IMarketHoursBreaker marketHoursBreaker;
  }

  /**
   * @notice Emitted when the SortedOracles contract is updated
   * @param oldSortedOracles Previous SortedOracles address
   * @param newSortedOracles New SortedOracles address
   */
  event SortedOraclesUpdated(address oldSortedOracles, address newSortedOracles);

  /**
   * @notice Emitted when the BreakerBox contract is updated
   * @param oldBreakerBox Previous BreakerBox address
   * @param newBreakerBox New BreakerBox address
   */
  event BreakerBoxUpdated(address oldBreakerBox, address newBreakerBox);

  /**
   * @notice Emitted when the MarketHoursBreaker contract is updated
   * @param oldMarketHoursBreaker Previous MarketHoursBreaker address
   * @param newMarketHoursBreaker New MarketHoursBreaker address
   */
  event MarketHoursBreakerUpdated(address oldMarketHoursBreaker, address newMarketHoursBreaker);

  /**
   * @notice Initializes the Adaptore contract
   * @param _sortedOracles The address of the sorted oracles contract
   * @param _breakerBox The address of the breaker box contract
   * @param _marketHoursBreaker The address of the market hours breaker contract
   */
  function initialize(address _sortedOracles, address _breakerBox, address _marketHoursBreaker) external;

  function sortedOracles() external view returns (ISortedOracles);

  function breakerBox() external view returns (IBreakerBox);

  function marketHoursBreaker() external view returns (IMarketHoursBreaker);

  function isMarketOpen() external view returns (bool);

  function hasValidRate(address rateFeedID) external view returns (bool);

  function getRate(address rateFeedID) external view returns (uint256, uint256);

  function getTradingMode(address rateFeedID) external view returns (uint8);
}
