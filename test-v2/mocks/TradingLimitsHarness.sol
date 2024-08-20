// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { TradingLimits } from "contracts/libraries/TradingLimits.sol";
import { ITradingLimitsHarness } from "./ITradingLimitsHarness.sol";

contract TradingLimitsHarness is ITradingLimitsHarness {
  using TradingLimits for TradingLimits.State;
  using TradingLimits for TradingLimits.Config;

  function validate(Config memory config) public view {
    return cast(config).validate();
  }

  function verify(State memory state, Config memory config) public view {
    return cast(state).verify(cast(config));
  }

  function reset(State memory state, Config memory config) public view returns (State memory) {
    return cast(cast(state).reset(cast(config)));
  }

  function update(
    State memory state,
    Config memory config,
    int256 netflow,
    uint8 decimals
  ) public view returns (State memory) {
    return cast(cast(state).update(cast(config), netflow, decimals));
  }

  function cast(Config memory config) internal pure returns (TradingLimits.Config memory) {
    return abi.decode(abi.encode(config), (TradingLimits.Config));
  }

  function cast(State memory state) internal pure returns (TradingLimits.State memory) {
    return abi.decode(abi.encode(state), (TradingLimits.State));
  }

  function cast(TradingLimits.Config memory config) internal pure returns (Config memory) {
    return abi.decode(abi.encode(config), (Config));
  }

  function cast(TradingLimits.State memory state) internal pure returns (State memory) {
    return abi.decode(abi.encode(state), (State));
  }
}
