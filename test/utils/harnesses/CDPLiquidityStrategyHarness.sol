// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { CDPLiquidityStrategy } from "contracts/v3/CDPLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

/**
 * @title CDPLiquidityStrategyHarness
 * @notice Test harness that exposes internal methods for testing
 */
contract CDPLiquidityStrategyHarness is CDPLiquidityStrategy {
  constructor(address _initialOwner) CDPLiquidityStrategy(_initialOwner) {}

  /**
   * @notice Exposes the internal _determineAction method for testing
   * @param ctx The liquidity context
   * @return action The determined rebalance action
   */
  function determineAction(LQ.Context memory ctx) external view returns (LQ.Action memory action) {
    return _determineAction(ctx);
  }
}
