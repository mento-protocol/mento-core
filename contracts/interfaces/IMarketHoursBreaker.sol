// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IBreaker } from "./IBreaker.sol";
import { IOwnable } from "./IOwnable.sol";

interface IMarketHoursBreaker is IBreaker, IOwnable {
  /**
   * @notice Check if the timestamp is inside fx market hours
   * @param timestamp The timestamp to check
   * @return True if the timestamp is inside fx market hours, false otherwise
   */
  function isMarketOpen(uint256 timestamp) external view returns (bool);

  /**
   * @notice Get the cooldown time for a rate feed
   * @param rateFeedID The rate feed to get the cooldown for
   * @return The cooldown time for the rate feed
   */
  function getCoolDown(address rateFeedID) external view returns (uint256);

  /**
   * @notice Set the cooldown time for a list of rate feeds
   * @param rateFeedIDs The rate feeds to set the cooldown for
   * @param cooldownTimes The cooldown times for the rate feeds
   */
  function setCooldownTimes(address[] calldata rateFeedIDs, uint256[] calldata cooldownTimes) external;

  /**
   * @notice Set the default cooldown time
   * @param cooldownTime The default cooldown time
   */
  function setDefaultCooldownTime(uint256 cooldownTime) external;

  /**
   * @notice Get the default cooldown time
   * @return The default cooldown time
   */
  function defaultCooldownTime() external view returns (uint256);
}
