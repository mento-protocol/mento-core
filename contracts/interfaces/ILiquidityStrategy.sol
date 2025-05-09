// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ILiquidityStrategy {
  /**
   * @notice Enum representing the direction of price deviation from the oracle price.
   * @dev Used to determine the direction of the price movement when rebalancing.
   */
  enum PriceDirection {
    ABOVE_ORACLE,
    BELOW_ORACLE
  }
  /**
   * @notice Struct holding the configuration of an FPMM pool.
   * @param lastRebalance The timestamp of the last rebalance for this pool.
   * @param rebalanceCooldown The cooldown period for the next rebalance.
   */
  struct FPMMConfig {
    uint256 lastRebalance;
    uint256 rebalanceCooldown;
  }

  /**
   * @notice Emitted after an FPMM pool is added.
   * @param pool The address of the pool that was added.
   * @param rebalanceCooldown The cooldown period for the next rebalance.
   */
  event FPMMPoolAdded(address indexed pool, uint256 rebalanceCooldown);

  /**
   * @notice Emitted when an FPMM pool is removed.
   * @param pool The address of the pool that was removed.
   */
  event FPMMPoolRemoved(address indexed pool);

  /**
   * @notice Emitted when a rebalance is initiated by the strategy.
   * @param pool The pool being rebalanced.
   * @param stableOut Amount of stable token being taken out of the pool.
   * @param collateralOut Amount of collateral being taken out of the pool.
   * @param inputAmount The amount the strategy is supplying in the callback.
   * @param direction ABOVE_ORACLE for contraction, BELOW_ORACLE for expansion.
   */
  event RebalanceInitiated(
    address indexed pool,
    uint256 stableOut,
    uint256 collateralOut,
    uint256 inputAmount,
    PriceDirection direction
  );

  /**
   * @notice Emitted when an FPMM pool is rebalanced.
   * @param pool The address of the pool that was rebalanced.
   * @param priceBefore The pool price before the rebalance.
   * @param priceAfter The pool price after the rebalance.
   */
  event RebalanceExecuted(address indexed pool, uint256 priceBefore, uint256 priceAfter);

  /**
   * @notice Emitted when a rebalance is skipped because the cooldown period has not elapsed.
   * @param pool The address of the pool that was skipped.
   */
  event RebalanceSkippedNotCool(address indexed pool);

  /**
   * @notice Emitted when a rebalance is skipped because the price is within the threshold.
   * @param pool The address of the pool that was skipped.
   */
  event RebalanceSkippedPriceInRange(address indexed pool);

  /**
   * @notice Triggers the liquidity rebalancing mechanism.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external;
}
