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

  function getCoolDown(address rateFeedID) external view returns (uint256);

  function setDefaultCooldownTime(uint256 cooldownTime) external;

  function setCooldownTimes(address[] calldata rateFeedIDs, uint256[] calldata cooldownTimes) external;

  function setDefaultRateChangeThreshold(uint256 _rateChangeTreshold) external;

  function setRateChangeThresholds(address[] calldata rateFeedIDs, uint256[] calldata rateChangeThresholds) external;

  function defaultCooldownTime() external view returns (uint256);

  function defaultRateChangeThreshold() external view returns (uint256);

  function rateChangeThreshold(address) external view returns (uint256);
}
