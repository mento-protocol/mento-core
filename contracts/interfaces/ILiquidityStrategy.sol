// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { LiquidityStrategyTypes as LQ } from "../libraries/LiquidityStrategyTypes.sol";

interface ILiquidityStrategy {
  /* ============================================================ */
  /* ===================== Structs & Enums ====================== */
  /* ============================================================ */

  /**
   * @notice Struct holding the complete configuration of an FPMM pool,
   *         in the context of liquidity management.
   * @param isToken0Debt Whether token0 is the debt token (true) or token1 is the debt token (false)
   * @param lastRebalance The timestamp of the last rebalance for this pool
   * @param rebalanceCooldown The cooldown period that must pass before the next rebalance
   */
  struct PoolConfig {
    bool isToken0Debt;
    uint64 lastRebalance;
    uint64 rebalanceCooldown;
  }

  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  /// @notice Thrown when the incentive is invalid or exceeds limits
  error LS_BAD_INCENTIVE();
  /// @notice Thrown when the callback sender is not the strategy itself
  error LS_INVALID_SENDER();
  /// @notice Thrown when the initial owner is address(0)
  error LS_INVALID_OWNER();
  /// @notice Thrown when attempting to rebalance before cooldown has elapsed
  error LS_COOLDOWN_ACTIVE();
  /// @notice Thrown when strategy execution fails
  error LS_STRATEGY_EXECUTION_FAILED();
  /// @notice Thrown when pool address is zero
  error LS_POOL_MUST_BE_SET();
  /// @notice Thrown when attempting to add a pool that already exists
  error LS_POOL_ALREADY_EXISTS();
  /// @notice Thrown when pool is not found in the registry
  error LS_POOL_NOT_FOUND();
  /// @notice Thrown when rebalance thresholds are invalid
  error LS_INVALID_THRESHOLD();
  /// @notice Thrown when token decimals are zero
  error LS_ZERO_DECIMAL();
  /// @notice Thrown when token decimals exceed 1e18
  error LS_INVALID_DECIMAL();
  /// @notice Thrown when oracle prices are invalid
  error LS_INVALID_PRICES();
  /// @notice Thrown when the hook callback isn't called during a rebalance from the FPMM
  error LS_HOOK_NOT_CALLED();
  /// @notice Thrown when the same pool is rebalanced twice in a single transaction
  error LS_CAN_ONLY_REBALANCE_ONCE(address pool);
  /// @notice Thrown when trying to add a pool with a debt token that's not a part of the pool
  error LS_DEBT_TOKEN_NOT_IN_POOL();

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  /**
   * @notice Emitted when a new pool is added to the strategy
   * @param pool The address of the pool
   * @param isToken0Debt Whether token0 is the debt token
   * @param cooldown The rebalance cooldown period
   * @param incentiveBps The rebalance incentive in basis points
   */
  event PoolAdded(address indexed pool, bool isToken0Debt, uint64 cooldown, uint32 incentiveBps);

  /**
   * @notice Emitted when a pool is removed from the strategy
   * @param pool The address of the pool
   */
  event PoolRemoved(address indexed pool);

  /**
   * @notice Emitted when a pool's rebalance cooldown is updated
   * @param pool The address of the pool
   * @param cooldown The new cooldown period
   */
  event RebalanceCooldownSet(address indexed pool, uint64 cooldown);

  /**
   * @notice Emitted when liquidity is moved during rebalance
   * @param pool The address of the pool
   * @param direction The direction of the rebalance (Expand or Contract)
   * @param tokenGivenToPool The token address moved into the pool
   * @param amountGivenToPool The amount of tokens moved into the pool
   * @param tokenTakenFromPool The token address taken from the pool
   * @param amountTakenFromPool The amount of tokens taken from the pool
   */
  event LiquidityMoved(
    address indexed pool,
    LQ.Direction indexed direction,
    address tokenGivenToPool,
    uint256 amountGivenToPool,
    address tokenTakenFromPool,
    uint256 amountTakenFromPool
  );

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Sets the rebalance cooldown for a given liquidity pool.
   * @param pool The address of the pool to update.
   * @param cooldown The new cooldown period for the pool.
   */
  function setRebalanceCooldown(address pool, uint64 cooldown) external;

  /**
   * @notice Executes a rebalance for the specified pool using its configured policy pipeline.
   * @dev Callable by anyone but subject to cooldown restrictions.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external;

  /**
   * @notice Hook called by FPMM during rebalance to handle token transfers
   * @dev Must be called by a registered pool with the correct sender
   * @param sender The address that initiated the rebalance (must be this contract)
   * @param amount0Out The amount of token0 to be sent from the pool
   * @param amount1Out The amount of token1 to be sent from the pool
   * @param data Encoded callback data containing rebalance parameters
   */
  function onRebalance(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external;

  /* ============================================================ */
  /* ======================== View Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Checks if a pool is registered with the controller.
   * @param pool The address of the pool to check.
   * @return True if the pool is registered, false otherwise.
   */
  function isPoolRegistered(address pool) external view returns (bool);

  /**
   * @notice Returns all registered pool addresses.
   * @return An array of all registered pool addresses.
   */
  function getPools() external view returns (address[] memory);

  /**
   * @notice Determines the rebalance action for a given pool based on current state
   * @dev View-only version of rebalance logic for external inspection
   * @param pool The address of the pool to analyze
   * @return ctx The liquidity context containing pool state and configuration
   * @return action The determined rebalance action with amounts and direction
   */
  function determineAction(address pool) external view returns (LQ.Context memory ctx, LQ.Action memory action);
}
