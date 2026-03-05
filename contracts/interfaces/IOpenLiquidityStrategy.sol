// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { ILiquidityStrategy } from "./ILiquidityStrategy.sol";

/**
 * @title IOpenLiquidityStrategy
 * @notice Interface for liquidity strategy where the rebalancer (caller) provides liquidity directly
 */
interface IOpenLiquidityStrategy is ILiquidityStrategy {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  /// @notice Thrown when the rebalancer has no collateral available for contraction
  error OLS_OUT_OF_COLLATERAL();
  /// @notice Thrown when the rebalancer has no debt tokens available for expansion
  error OLS_OUT_OF_DEBT();

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Initializes the OpenLiquidityStrategy contract
   * @param _initialOwner The initial owner of the contract
   */
  function initialize(address _initialOwner) external;

  /**
   * @notice Adds a new liquidity pool to be managed by the strategy
   * @param params The parameters for adding a pool
   */
  function addPool(AddPoolParams calldata params) external;

  /**
   * @notice Removes a pool from the strategy
   * @param pool The address of the pool to remove
   */
  function removePool(address pool) external;
}
