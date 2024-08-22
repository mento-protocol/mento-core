// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { TradingLimits } from "contracts/libraries/TradingLimits.sol";
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { ITradingLimitsHarness } from "./ITradingLimitsHarness.sol";

contract TradingLimitsHarness is ITradingLimitsHarness {
  using TradingLimits for ITradingLimits.State;
  using TradingLimits for ITradingLimits.Config;

  function validate(ITradingLimits.Config memory config) public view {
    return config.validate();
  }

  function verify(ITradingLimits.State memory state, ITradingLimits.Config memory config) public view {
    return state.verify(config);
  }

  function reset(
    ITradingLimits.State memory state,
    ITradingLimits.Config memory config
  ) public view returns (ITradingLimits.State memory) {
    return state.reset(config);
  }

  function update(
    ITradingLimits.State memory state,
    ITradingLimits.Config memory config,
    int256 netflow,
    uint8 decimals
  ) public view returns (ITradingLimits.State memory) {
    return state.update(config, netflow, decimals);
  }
}
