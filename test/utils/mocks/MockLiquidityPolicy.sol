// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { ILiquidityPolicy } from "contracts/v3/Interfaces/ILiquidityPolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract MockLiquidityPolicy is ILiquidityPolicy {
  bool public shouldAct;
  LQ.Action public action;
  bool public executed;

  function name() external pure returns (string memory) {
    return "MockLiquidityStrategy";
  }

  function setShouldAct(bool _shouldAct) external {
    shouldAct = _shouldAct;
  }

  function setAction(LQ.Action memory _action) external {
    action = _action;
  }

  function determineAction(LQ.Context memory) external view returns (bool, LQ.Action memory) {
    // Note: We can't track execution here since it's a view function
    // Instead, we'll need a different approach in the test
    return (shouldAct, action);
  }

  function markExecuted() external {
    executed = true;
  }

  function wasExecuted() external view returns (bool) {
    return executed;
  }
}
