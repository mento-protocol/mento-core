// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

// import { IBreaker } from "../../interfaces/IBreaker.sol";
import { IMarketHoursBreaker } from "../../interfaces/IMarketHoursBreaker.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

import { BokkyPooBahsDateTimeLibrary } from "BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";
// import { WithCooldownV2 } from "./WithCooldownV2.sol";

contract MarketHoursBreaker is IMarketHoursBreaker {
  /* ========== CONSTRUCTOR ========== */
  /**
   * @notice Contract constructor
   */
  constructor() {
    // _transferOwnership(msg.sender);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
   * @notice Check if the timestamp is inside fx market hours
   * @param timestamp The timestamp to check
   * @return True if the timestamp is inside fx market hours, false otherwise
   */
  function isMarketOpen(uint256 timestamp) public view returns (bool) {
    return !_isWeekendHours(timestamp) && !_isHoliday(timestamp);
  }

  /* ========== EXTERNAL FUNCTIONS ========== */

  /**
   * @notice  Check if the timestamp is outside of fx market hours or on a holiday,
   *          in which case the breaker will be triggered.
   * @param   rateFeedID The rate feed to be checked. Unused in this implementation as market hours
   *          in this breaker are not rate feed dependent.
   * @return  triggerBreaker True if the timestamp is outside of fx market hours or on a holiday, false otherwise
   */
  // solhint-disable-next-line no-unused-vars
  function shouldTrigger(address rateFeedID) public returns (bool triggerBreaker) {
    require(isMarketOpen(block.timestamp), "MarketHoursBreaker: Market is closed");

    return false;
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * @notice Check if the timestamp is during FX weekend hours
   * @param timestamp The timestamp to check
   * @return True if the timestamp is during FX weekend hours, false otherwise
   */
  function _isWeekendHours(uint256 timestamp) internal view returns (bool) {
    uint256 dow = BokkyPooBahsDateTimeLibrary.getDayOfWeek(timestamp);
    uint256 hour = BokkyPooBahsDateTimeLibrary.getHour(timestamp);

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
  function _isHoliday(uint256 timestamp) internal view returns (bool) {
    uint256 month = BokkyPooBahsDateTimeLibrary.getMonth(timestamp);
    uint256 day = BokkyPooBahsDateTimeLibrary.getDay(timestamp);

    // slither-disable-next-line incorrect-equality
    return ((month == 12 && day == 25) || (month == 1 && day == 1));
  }
}
