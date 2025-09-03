// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IBreaker } from "../../interfaces/IBreaker.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";

import { BokkyPooBahsDateTimeLibrary } from "BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";
import { WithCooldownV2 } from "./WithCooldownV2.sol";

contract MarketHoursBreaker is IBreaker, WithCooldownV2, Ownable {
  /* ========== CONSTRUCTOR ========== */
  /**
   * @notice Contract constructor
   * @param _defaultCooldownTime The default cooldown time
   */
  constructor(uint256 _defaultCooldownTime) {
    _transferOwnership(msg.sender);

    _setDefaultCooldownTime(_defaultCooldownTime);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
   * @notice Get the cooldown time for a rate feed
   * @param rateFeedID The rate feed to get the cooldown for
   * @return The cooldown time for the rate feed
   */
  function getCooldown(address rateFeedID) public view override(WithCooldownV2, IBreaker) returns (uint256) {
    return WithCooldownV2.getCooldown(rateFeedID);
  }

  /* ========== ADMIN FUNCTIONS ========== */

  /**
   * @notice Set the cooldown time for a list of rate feeds
   * @param rateFeedIDs The rate feeds to set the cooldown for
   * @param cooldownTimes The cooldown times for the rate feeds
   */
  function setCooldownTimes(address[] calldata rateFeedIDs, uint256[] calldata cooldownTimes) external onlyOwner {
    _setCooldownTimes(rateFeedIDs, cooldownTimes);
  }

  /**
   * @notice Set the default cooldown time
   * @param cooldownTime The default cooldown time
   */
  function setDefaultCooldownTime(uint256 cooldownTime) external onlyOwner {
    _setDefaultCooldownTime(cooldownTime);
  }

  /* ========== EXTERNAL FUNCTIONS ========== */

  /**
   * @notice  Check if the timestamp is outside of fx market hours or on a holiday,
   *          in which case the breaker will be triggered.
   * @param   rateFeedID The rate feed to be checked
   * @return  triggerBreaker True if the timestamp is outside of fx market hours or on a holiday, false otherwise
   */
  // solhint-disable-next-line no-unused-vars
  function shouldTrigger(address rateFeedID) public returns (bool triggerBreaker) {
    return !isMarketOpen(block.timestamp);
  }

  /**
   * @notice  Checks whether or not the conditions have been met
   *          for the specifed rate feed to be reset.
   * @return  resetBreaker A bool indicating whether or not
   *          this breaker can be reset for the given rate feed.
   */
  function shouldReset(address rateFeedID) external returns (bool resetBreaker) {
    return !shouldTrigger(rateFeedID);
  }

  /**
   * @notice Check if the timestamp is inside fx market hours
   * @param timestamp The timestamp to check
   * @return True if the timestamp is inside fx market hours, false otherwise
   */
  function isMarketOpen(uint256 timestamp) public view returns (bool) {
    return !_isWeekendHours(timestamp) && !_isHoliday(timestamp);
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

    bool isFridayEvening = dow == 5 && hour >= 21;
    bool isSaturday = dow == 6;
    bool isSundayBeforeEvening = dow == 7 && hour < 23;

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

    return ((month == 12 && day == 25) || (month == 1 && day == 1));
  }
}
