// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IMarketHoursBreaker } from "../../interfaces/IMarketHoursBreaker.sol";

// solhint-disable-next-line max-line-length
import { BokkyPooBahsDateTimeLibrary as DateTimeLibrary } from "BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";

/**
 * @title MarketHoursBreaker
 * @notice A special type of breaker that reverts if called outside of fx market hours or on holidays.
 *         Used to enforce that FX rates are only being reported during valid trading hours.
 */
contract MarketHoursBreaker is IMarketHoursBreaker {
  /* ========== VIEW FUNCTIONS ========== */

  /// @inheritdoc IMarketHoursBreaker
  function isMarketOpen(uint256 timestamp) public pure returns (bool) {
    return !_isWeekendHours(timestamp) && !_isHoliday(timestamp);
  }

  /// @inheritdoc IMarketHoursBreaker
  // solhint-disable-next-line no-unused-vars
  function shouldTrigger(address rateFeedID) public view returns (bool triggerBreaker) {
    require(isMarketOpen(block.timestamp), "MarketHoursBreaker: Market is closed");

    return false;
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * @notice Check if the timestamp is during FX weekend hours
   * @param timestamp The timestamp to check
   * @return True if the timestamp is during FX weekend hours, false otherwise
   */
  function _isWeekendHours(uint256 timestamp) internal pure returns (bool) {
    uint256 dow = DateTimeLibrary.getDayOfWeek(timestamp);
    uint256 hour = DateTimeLibrary.getHour(timestamp);

    // slither-disable-start incorrect-equality
    bool isFridayEvening = dow == 5 && hour >= 21;
    bool isSaturday = dow == 6;
    bool isSundayBeforeEvening = dow == 7 && hour < 23;
    // slither-disable-end

    return isFridayEvening || isSaturday || isSundayBeforeEvening;
  }

  /**
   * @notice Check if the timestamp is during FX holidays
   * @param timestamp The timestamp to check
   * @return True if the timestamp is during FX holidays, false otherwise
   */
  function _isHoliday(uint256 timestamp) internal pure returns (bool) {
    uint256 month = DateTimeLibrary.getMonth(timestamp);
    uint256 day = DateTimeLibrary.getDay(timestamp);

    // slither-disable-next-line incorrect-equality
    return ((month == 12 && day == 25) || (month == 1 && day == 1));
  }
}
