// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { ILiquidityStrategy } from "contracts/v3/Interfaces/ILiquidityStrategy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract MockLiquidityStrategy is ILiquidityStrategy {
  bool public executionResult = true;
  bytes public lastCallback;
  LQ.Action public lastAction;
  bytes public executionCallback;

  // Execution tracking for testing
  uint256 public executionCount;
  uint256 public lastInputAmount;

  function setExecutionResult(bool _result) external {
    executionResult = _result;
  }

  function setExecutionCallback(bytes memory _callback) external {
    executionCallback = _callback;
  }

  function execute(LQ.Action memory _action, bytes memory _callback) external returns (bool) {
    lastAction = _action;
    lastCallback = _callback;

    // Track execution count
    executionCount++;

    // Decode and track input amount for testing
    if (_callback.length > 0) {
      (uint256 inputAmount, , , , , ) = abi.decode(
        _callback,
        (uint256, LQ.Direction, uint256, LQ.LiquiditySource, bool, bytes)
      );
      lastInputAmount = inputAmount;
    }

    // Execute callback if set (to simulate price changes after execution)
    if (executionCallback.length > 0) {
      (bool success, ) = _action.pool.call(executionCallback);
      require(success, "Callback failed");
    }

    return executionResult;
  }

  // Reset tracking state for cleaner test setup
  function resetTracking() external {
    executionCount = 0;
    lastInputAmount = 0;
  }
}
