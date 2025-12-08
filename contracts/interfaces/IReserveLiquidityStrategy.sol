// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { ILiquidityStrategy } from "./ILiquidityStrategy.sol";
import { IReserveV2 } from "./IReserveV2.sol";

/**
 * @title IReserveLiquidityStrategy
 * @notice Interface for liquidity strategy that uses the Mento Reserve for liquidity provision
 */
interface IReserveLiquidityStrategy is ILiquidityStrategy {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  /// @notice Thrown when the reserve address is invalid (zero address)
  error RLS_INVALID_RESERVE();
  /// @notice Thrown when the reserve has no collateral available for contraction
  error RLS_RESERVE_OUT_OF_COLLATERAL();
  /// @notice Thrown when collateral transfer from reserve to pool fails
  error RLS_COLLATERAL_TO_POOL_FAILED();
  /// @notice Thrown when the input token is not supported by the reserve
  error RLS_TOKEN_IN_NOT_SUPPORTED();
  /// @notice Thrown when the output token is not supported by the reserve
  error RLS_TOKEN_OUT_NOT_SUPPORTED();

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  /**
   * @notice Emitted when the reserve address is updated
   * @param oldReserve The previous reserve address
   * @param newReserve The new reserve address
   */
  event ReserveSet(address indexed oldReserve, address indexed newReserve);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Adds a new liquidity pool to be managed by the strategy
   * @param pool The address of the FPMM pool to add
   * @param debtToken The address of the debt token (stable asset)
   * @param cooldown The cooldown period between rebalances in seconds
   * @param liquiditySourceIncentiveBpsExpansion The incentive for the liquidity source in basis points for expansion
   * @param protocolIncentiveBpsExpansion The incentive for the protocol in basis points for expansion
   * @param liquiditySourceIncentiveBpsContraction The incentive for the liquidity source in basis points for contraction
   * @param protocolIncentiveBpsContraction The incentive for the protocol in basis points for contraction
   * @param protocolFeeRecipient The recipient of the protocol fee
   */
  function addPool(
    address pool,
    address debtToken,
    uint64 cooldown,
    uint128 liquiditySourceIncentiveBpsExpansion,
    uint128 protocolIncentiveBpsExpansion,
    uint128 liquiditySourceIncentiveBpsContraction,
    uint128 protocolIncentiveBpsContraction,
    address protocolFeeRecipient
  ) external;

  /**
   * @notice Removes a pool from the strategy
   * @param pool The address of the pool to remove
   */
  function removePool(address pool) external;

  /**
   * @notice Sets the reserve contract address
   * @param _reserve The new reserve contract address
   */
  function setReserve(address _reserve) external;

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  /**
   * @notice Returns the reserve contract
   * @return The reserve contract interface
   */
  function reserve() external view returns (IReserveV2);
}
