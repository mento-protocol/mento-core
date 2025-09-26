// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { ILiquidityStrategy } from "contracts/v3/Interfaces/ILiquidityStrategy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract MockLiquidityStrategy is ILiquidityStrategy {
  bool public executionResult = true;
  LQ.Action public lastAction;
  bytes public executionCallback;

  // Execution tracking for testing
  uint256 public executionCount;
  uint256 public lastInputAmount;
  uint256 public lastIncentiveAmount;
  bool public lastIsToken0Debt;

  function setExecutionResult(bool _result) external {
    executionResult = _result;
  }

  function setExecutionCallback(bytes memory _callback) external {
    executionCallback = _callback;
  }

  function execute(LQ.Action calldata _action) external returns (bool) {
    lastAction = _action;

    // Track execution count
    executionCount++;
    lastInputAmount = _action.inputAmount;

    // Decode action data if present
    if (_action.data.length > 0) {
      (uint256 incentiveAmount, bool isToken0Debt) = abi.decode(_action.data, (uint256, bool));
      lastIncentiveAmount = incentiveAmount;
      lastIsToken0Debt = isToken0Debt;
    }

    // Execute callback if set (to simulate price changes after execution)
    if (executionCallback.length > 0) {
      // solhint-disable-next-line avoid-low-level-calls
      (bool success, ) = _action.pool.call(executionCallback);
      require(success, "Callback failed");
    }

    return executionResult;
  }

  // Reset tracking state for cleaner test setup
  function resetTracking() external {
    executionCount = 0;
    lastInputAmount = 0;
    lastIncentiveAmount = 0;
    lastIsToken0Debt = false;
  }
}
