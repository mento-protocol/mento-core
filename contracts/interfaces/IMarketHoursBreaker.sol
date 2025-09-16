// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IMarketHoursBreaker {
  /**
   * @notice Check if the timestamp is inside fx market hours
   * @param timestamp The timestamp to check
   * @return True if the timestamp is inside fx market hours, false otherwise
   */
  function isMarketOpen(uint256 timestamp) external pure returns (bool);

  /**
   * @notice  Enforces that the market is open during valid trading hours.
   *          This function reverts if called outside of fx market hours or on holidays.
   * @param   rateFeedID The rate feed to be checked. Unused in this implementation as market hours
   *          in this breaker are not rate feed dependent.
   * @return  triggerBreaker Always returns false if execution completes (market is open),
   *          And reverts if the market is closed.
   * @dev     This function implements the IBreaker interface but uses a revert-on-condition
   *          pattern rather than returning true/false. The boolean return is required by the
   *          interface but will only be reached when the condition passes (market open).
   */
  function shouldTrigger(address rateFeedID) external view returns (bool triggerBreaker);
}
