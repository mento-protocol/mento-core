// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { ITradingLimitsV2 } from "contracts/interfaces/ITradingLimitsV2.sol";

interface ITradingLimitsV2Harness {
  function validate(ITradingLimitsV2.Config memory config) external pure;

  function verify(ITradingLimitsV2.State memory state, ITradingLimitsV2.Config memory config) external pure;

  function reset(
    ITradingLimitsV2.State memory state,
    ITradingLimitsV2.Config memory config
  ) external pure returns (ITradingLimitsV2.State memory);

  function update(
    ITradingLimitsV2.State memory state,
    ITradingLimitsV2.Config memory config,
    int256 deltaFlow
  ) external view returns (ITradingLimitsV2.State memory);

  function scaleValue(int256 value, uint8 decimals) external pure returns (int96);

  function safeAdd(int96 a, int96 b) external pure returns (int96);
}
