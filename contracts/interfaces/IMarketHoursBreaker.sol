// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IBreaker } from "./IBreaker.sol";

interface IRevertBreaker {
  function shouldTrigger(address rateFeedID) external returns (bool triggerBreaker);
}

interface IMarketHoursBreaker is IRevertBreaker {
  function isMarketOpen(uint256 timestamp) external view returns (bool);

  // function getCoolDown(address rateFeedID) external view returns (uint256);

  // function setCooldownTimes(address[] calldata rateFeedIDs, uint256[] calldata cooldownTimes) external;

  // function setDefaultCooldownTime(uint256 cooldownTime) external;

  // function defaultCooldownTime() external view returns (uint256);
}
