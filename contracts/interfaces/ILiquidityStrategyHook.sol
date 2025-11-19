// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title Liquidity Strategy hook interface
 * @author Mento Labs
 * @notice This interface allows for callback functionality during liquidity strategy rebalances
 */
interface ILiquidityStrategyHook {
  /**
   * @notice Hook called by FPMM during rebalance after tokens
   * have been transferred from the pool to the liquidity strategy.
   * @param sender The address that initiated the rebalance (must be a LiquidityStrategy)
   * @param amount0Out The amount of token0 sent from the pool
   * @param amount1Out The amount of token1 sent from the pool
   * @param data Encoded callback data containing rebalance parameters
   */
  function onRebalance(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external;
}
