// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ILiquidityStrategy {
  /**
   * @notice Struct holding the state of a pool.
   * @param lastRebalance The timestamp of the last rebalance for this pool.
   */
  struct PoolState {
    uint256 lastRebalance;
  }

  /**
   * @notice Emitted when a pool is rebalanced.
   * @param pool The address of the pool that was rebalanced.
   * @param priceBefore The pool price before the rebalance.
   * @param priceAfter The pool price after the rebalance.
   */
  event Rebalance(address indexed pool, uint256 priceBefore, uint256 priceAfter);

  /**
   * @notice Triggers the liquidity rebalancing mechanism.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external;
}
