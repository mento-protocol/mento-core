// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { LiquidityStrategyTypes as LQ } from "../libraries/LiquidityStrategyTypes.sol";

interface ILiquidityController {
  /* ============================================================ */
  /* ===================== Structs & Enums ====================== */
  /* ============================================================ */

  /**
   * @notice Struct holding the complete configuration of an FPMM pool,
   *         in the context of liquidity management.
   * @param debtToken The Mento-issued debt token (e.g., cUSD, USD.M etc)
   * @param collateralToken The backing/collateral token (e.g., USDC, USDT)
   * @param lastRebalance The timestamp of the last rebalance for this pool.
   * @param rebalanceCooldown The cooldown period that must pass before the next rebalance.
   * @param rebalanceIncentive The controller-side incentive cap (bps) for the rebalance.
   */
  struct PoolConfig {
    address debtToken;
    address collateralToken;
    uint128 lastRebalance;
    uint64 rebalanceCooldown;
    uint32 rebalanceIncentive;
  }

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  event PoolAdded(address indexed pool, address debt, address collateral, uint64 cooldown, uint32 incentiveBps);
  event PoolRemoved(address indexed pool);
  event RebalanceCooldownSet(address indexed pool, uint64 cooldown);
  event RebalanceIncentiveSet(address indexed pool, uint32 incentiveBps);
  event RebalanceExecuted(address indexed pool, uint256 diffBeforeBps, uint256 diffAfterBps);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Adds a new liquidity pool to be mangeed by the controller.
   * @param pool The address of the pool to be added
   * @param debtToken The address of the pools debt token
   * @param collateralToken The address of the pools collateral token
   * @param cooldown The cooldown period that must elapse before the pool can be rebalanced again
   * @param incentiveBps The rebalance incentive in basis points
   */
  function addPool(
    address pool,
    address debtToken,
    address collateralToken,
    uint64 cooldown,
    uint32 incentiveBps
  ) external;

  /**
   * @notice Removes a liquidity pool from the controller.
   * @param pool The address of the pool to be removed.
   */
  function removePool(address pool) external;

  /**
   * @notice Sets the rebalance cooldown for a given liquidity pool.
   * @param pool The address of the pool to update.
   * @param cooldown The new cooldown period for the pool.
   */
  function setRebalanceCooldown(address pool, uint64 cooldown) external;

  /**
   * @notice Sets the rebalance incentive for a given liquidity pool.
   * @param pool The address of the pool to update.
   * @param incentiveBps The new incentive in basis points.
   */
  function setRebalanceIncentive(address pool, uint32 incentiveBps) external;

  /**
   * @notice Executes a rebalance for the specified pool using its configured policy pipeline.
   * @dev Callable by anyone but subject to cooldown restrictions.
   * @param pool The address of the pool to rebalance.
   */
  function rebalance(address pool) external;

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
}
