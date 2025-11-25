// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { ILiquidityStrategy } from "./ILiquidityStrategy.sol";

/**
 * @title ICDPLiquidityStrategy
 * @notice Interface for liquidity strategy that uses CDP (Collateralized Debt Position) protocols
 * @dev This strategy integrates with stability pools for expansions and redemption mechanisms for contractions
 */
interface ICDPLiquidityStrategy is ILiquidityStrategy {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  /// @notice Thrown when the stability pool balance is below the minimum required threshold
  error CDPLS_STABILITY_POOL_BALANCE_TOO_LOW();
  /// @notice Thrown when the redemption fee exceeds the maximum incentive fee
  error CDPLS_REDEMPTION_FEE_TOO_LARGE();
  /// @notice Thrown when the stability pool percentage is invalid (must be 0 < percentage < 10000)
  error CDPLS_INVALID_STABILITY_POOL_PERCENTAGE();
  /// @notice Thrown when the collateral registry address is zero
  error CDPLS_COLLATERAL_REGISTRY_IS_ZERO();
  /// @notice Thrown when the stability pool address is zero
  error CDPLS_STABILITY_POOL_IS_ZERO();

  /* ============================================================ */
  /* ======================= Structs ============================ */
  /* ============================================================ */

  /**
   * @notice Configuration for CDP-specific parameters for a pool
   * @param stabilityPool The address of the stability pool used for swapping collateral to stable
   * @param collateralRegistry The address of the collateral registry for redemptions
   * @param systemParams The address of the system params contract for reading redemption beta
   * @param stabilityPoolPercentage The percentage of stability pool balance available for rebalancing (in bps)
   * @param maxIterations The maximum number of iterations for redemption operations
   */
  struct CDPConfig {
    address stabilityPool;
    address collateralRegistry;
    address systemParams;
    uint256 stabilityPoolPercentage;
    uint256 maxIterations;
  }

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Adds a new liquidity pool to be managed by the CDP strategy
   * @param pool The address of the FPMM pool to add
   * @param debtToken The address of the debt token (stable asset)
   * @param cooldown The cooldown period between rebalances in seconds
   * @param incentiveBps The rebalance incentive in basis points
   * @param stabilityPool The address of the stability pool for this debt token
   * @param collateralRegistry The address of the collateral registry for redemptions
   * @param systemParams The address of the system params contract for reading redemption beta
   * @param stabilityPoolPercentage The percentage of stability pool balance to use (in bps)
   * @param maxIterations The maximum number of iterations for redemption operations
   */
  function addPool(
    address pool,
    address debtToken,
    uint64 cooldown,
    uint32 incentiveBps,
    address stabilityPool,
    address collateralRegistry,
    address systemParams,
    uint256 stabilityPoolPercentage,
    uint256 maxIterations
  ) external;

  /**
   * @notice Removes a pool from the strategy
   * @param pool The address of the pool to remove
   */
  function removePool(address pool) external;

  /**
   * @notice Updates the CDP-specific configuration for a pool
   * @param pool The address of the pool to configure
   * @param config The new CDP configuration
   */
  function setCDPConfig(address pool, CDPConfig calldata config) external;

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  /**
   * @notice Retrieves the CDP configuration for a given pool
   * @param pool The address of the pool
   * @return The CDP configuration
   */
  function getCDPConfig(address pool) external view returns (CDPConfig memory);
}
