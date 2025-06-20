// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ILiquidityStrategy {
  /* ==================== Enums & Structs ==================== */

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
   * @param rebalanceIncentive The incentive for the rebalance.
   */
  struct FPMMConfig {
    uint256 lastRebalance;
    uint256 rebalanceCooldown;
    uint256 rebalanceIncentive;
  }

  /* ==================== Events ==================== */

  /**
   * @notice Emitted after an FPMM pool is added.
   * @param pool The address of the pool that was added.
   * @param rebalanceCooldown The cooldown period for the next rebalance.
   * @param rebalanceIncentive The rebalance incentive in basis points.
   */
  event FPMMPoolAdded(address indexed pool, uint256 rebalanceCooldown, uint256 rebalanceIncentive);

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
   * @param incentiveAmount The amount of incentive being supplied in the callback.
   * @param direction ABOVE_ORACLE for contraction, BELOW_ORACLE for expansion.
   */
  event RebalanceInitiated(
    address indexed pool,
    uint256 stableOut,
    uint256 collateralOut,
    uint256 inputAmount,
    uint256 incentiveAmount,
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
   * @notice Emitted when the rebalance incentive is set.
   * @param pool The address of the pool the rebalance incentive was set for.
   * @param rebalanceIncentive The new rebalance incentive in basis points.
   */
  event RebalanceIncentiveSet(address indexed pool, uint256 rebalanceIncentive);

  /**
   * @notice Emitted when the rebalance cooldown is set.
   * @param pool The address of the pool the rebalance cooldown was set for.
   * @param rebalanceCooldown The new rebalance cooldown in seconds.
   */
  event RebalanceCooldownSet(address indexed pool, uint256 rebalanceCooldown);

  /**
   * @notice Emitted when tokens are withdrawn from the strategy.
   * @param tokenAddress The address of the token that was withdrawn.
   * @param recipient The address that received the tokens.
   * @param amount The amount of tokens that were withdrawn.
   */
  event Withdraw(address indexed tokenAddress, address indexed recipient, uint256 amount);

  /* ==================== Functions ==================== */

  /**
   * @notice Adds an FPMM pool.
   * @param pool The address of the pool to add.
   * @param cooldown The cooldown period for the next rebalance of the pool.
   * @param rebalanceIncentive The rebalance incentive in basis points.
   */
  function addPool(address pool, uint256 cooldown, uint256 rebalanceIncentive) external;

  /**
   * @notice Removes an FPMM pool.
   * @param pool The address of the pool to be removed.
   */
  function removePool(address pool) external;

  /**
   * @notice Triggers the rebalancing process for a pool.
   *         Obtains the pre-rebalance price, executes rebalancing logic,
   *         updates the pool's state, and emits an event with the pricing information.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external;

  /**
   * @notice Checks if a pool is registered.
   * @param pool The address of the pool to check.
   * @return True if the pool is registered, false otherwise.
   */
  function isPoolRegistered(address pool) external view returns (bool);

  /**
   * @notice Returns all registered pools.
   * @return An array of pool addresses.
   */
  function getPools() external view returns (address[] memory);
}
