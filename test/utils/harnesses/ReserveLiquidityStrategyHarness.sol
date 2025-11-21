// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { ReserveLiquidityStrategy } from "contracts/liquidityStrategies/ReserveLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";

/**
 * @title ReserveLiquidityStrategyHarness
 * @notice Test harness that exposes internal methods for testing
 */
contract ReserveLiquidityStrategyHarness is ReserveLiquidityStrategy {
  constructor(address _initialOwner, address _reserve) ReserveLiquidityStrategy(false) {
    initialize(_initialOwner, _reserve);
  }

  /**
   * @notice Exposes the internal _determineAction method for testing
   * @param ctx The liquidity context
   * @return action The determined rebalance action
   */
  function determineAction(LQ.Context memory ctx) external view returns (LQ.Action memory action) {
    return _determineAction(ctx);
  }
}
