// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;
pragma experimental ABIEncoderV2;

import { TradingLimitsV2 } from "contracts/libraries/TradingLimitsV2.sol";
import { ITradingLimitsV2 } from "contracts/interfaces/ITradingLimitsV2.sol";
import { ITradingLimitsV2Harness } from "./ITradingLimitsV2Harness.sol";

contract TradingLimitsV2Harness is ITradingLimitsV2Harness {
  using TradingLimitsV2 for ITradingLimitsV2.State;
  using TradingLimitsV2 for ITradingLimitsV2.Config;

  function validate(ITradingLimitsV2.Config memory config) public pure {
    return config.validate();
  }

  function verify(ITradingLimitsV2.State memory state, ITradingLimitsV2.Config memory config) public pure {
    return state.verify(config);
  }

  function reset(
    ITradingLimitsV2.State memory state,
    ITradingLimitsV2.Config memory config
  ) public pure returns (ITradingLimitsV2.State memory) {
    return state.reset(config);
  }

  function update(
    ITradingLimitsV2.State memory state,
    ITradingLimitsV2.Config memory config,
    int256 deltaFlow
  ) public view returns (ITradingLimitsV2.State memory) {
    return state.update(config, deltaFlow);
  }

  function scaleValue(int256 value, uint8 decimals) public pure returns (int96) {
    return TradingLimitsV2.scaleValue(value, decimals);
  }

  function safeAdd(int96 a, int96 b) public pure returns (int96) {
    return TradingLimitsV2.safeAdd(a, b);
  }
}
