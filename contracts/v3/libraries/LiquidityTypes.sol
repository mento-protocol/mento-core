// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { console } from "forge-std/console.sol";
/**
 * @title LiquidityTypes
 * @author Mento Labs
 * @notice Shared types and helpers for the Liquidity Controller, Policies & Strategies.
 */
library LiquidityTypes {
  /* ============================================================ */
  /* ====================== Constants =========================== */
  /* ============================================================ */

  uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;

  /* ============================================================ */
  /* ======================= Enums ============================== */
  /* ============================================================ */

  /**
   * @notice Indicates how the pool should be rebalanced relative to the oracle price.
   * @dev
   * - Expand:   Pool price > oracle price (PP > P).
   *             Rebalance by moving debt tokens into the pool and taking collateral out.
   * - Contract: Pool price < oracle price (PP < P).
   *             Rebalance by moving collateral into the pool and taking debt tokens out.
   */
  enum Direction {
    Expand,
    Contract
  }

  /// @notice Indicates where the liquidity comes from
  enum LiquiditySource {
    Reserve,
    CDP
  }

  /* ============================================================ */
  /* ======================= Structs ============================ */
  /* ============================================================ */

  /// @notice Struct to store the reserves of the FPMM pool
  struct Reserves {
    uint256 reserveNum;
    uint256 reserveDen;
  }

  /// @notice Price snapshot and deviation info
  struct Prices {
    uint256 oracleNum;
    uint256 oracleDen;
    bool poolPriceAbove;
    uint256 diffBps; // PP - P in bps
  }

  /// @notice Read-only context provided by the controller to a policy
  struct Context {
    address pool;
    Reserves reserves;
    Prices prices;
    address token0;
    address token1;
    uint128 incentiveBps;
    uint64 token0Dec;
    uint64 token1Dec;
    bool isToken0Debt;
  }

  /// @notice A single rebalance step produced by a policy
  struct Action {
    address pool;
    Direction dir;
    LiquiditySource liquiditySource;
    uint256 amount0Out; // amount of token0 to move out of pool
    uint256 amount1Out; // amount of token1 to move out of pool
    uint256 inputAmount; // amount moved into pool (pre-incentive)
    uint256 incentiveBps; // incentive bps applied to inputAmount
    bytes data; // strategy-specific data (optional)
  }

  /* ============================================================ */
  /* =================== Helper Functions ======================= */
  /* ============================================================ */

  /**
   * @notice Normalize a token amount to 18 decimals given its raw decimal factor.
   * @param amount raw token units
   * @param tokenDecimalsFactor 10**decimals (e.g., 1e6 for USDC, 1e18 for Mento tokens)
   * @dev There is no guard on tokenDecimalsFactor as it's expected that this function is used on context
   *      data that has been validated by the LiquidityController. If necessary, guard at the caller site.
   */
  function to1e18(uint256 amount, uint256 tokenDecimalsFactor) internal pure returns (uint256) {
    return amount * (1e18 / tokenDecimalsFactor);
  }

  /**
   * @notice Convert a 18d-normalized amount back to raw token units.
   * @param amount18 18d-normalized token units
   * @param tokenDecimalsFactor 10**decimals (e.g., 1e6 for USDC, 1e18 for Mento tokens)
   * @dev There is no guard on tokenDecimalsFactor as it's expected that this function is used on context
   *      data that has been validated by the LiquidityController. If necessary, guard at the caller site.
   */
  function from1e18(uint256 amount18, uint256 tokenDecimalsFactor) internal pure returns (uint256) {
    return amount18 / (1e18 / tokenDecimalsFactor);
  }

  function scaleFromTo(uint256 amount, uint256 fromDec, uint256 toDec) internal pure returns (uint256) {
    return (amount * toDec) / fromDec;
  }

  function convertWithRateScaling(
    uint256 amount,
    uint256 fromDec,
    uint256 toDec,
    uint256 oracleNum,
    uint256 oracleDen
  ) internal pure returns (uint256) {
    return (amount * oracleNum * toDec) / (fromDec * oracleDen);
  }

  function convertWithRateScalingAndFee(
    uint256 amount,
    uint256 fromDec,
    uint256 toDec,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 incentiveNum,
    uint256 incentiveDen
  ) internal pure returns (uint256) {
    return (amount * oracleNum * toDec * incentiveNum) / (fromDec * oracleDen * incentiveDen);
  }

  /// @notice Calc an amount in bps.
  function mulBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
    return (amount * bps) / BASIS_POINTS_DENOMINATOR;
  }

  /// @notice Incentive amount for a given input and bps.
  function incentiveAmount(uint256 inputAmount, uint256 incentiveBps) internal pure returns (uint256) {
    return mulBps(inputAmount, incentiveBps);
  }

  /// @notice Convert debt/collateral amounts to token order based on isToken0Debt.
  function toTokenOrder(
    uint256 debtOut,
    uint256 collateralOut,
    bool isToken0Debt
  ) internal pure returns (uint256 amount0Out, uint256 amount1Out) {
    if (isToken0Debt) return (debtOut, collateralOut);
    return (collateralOut, debtOut);
  }

  /// @notice Convert token order amounts back to debt/collateral based on isToken0Debt.
  function fromTokenOrder(
    uint256 amount0Out,
    uint256 amount1Out,
    bool isToken0Debt
  ) internal pure returns (uint256 debtOut, uint256 collateralOut) {
    if (isToken0Debt) return (amount0Out, amount1Out);
    return (amount1Out, amount0Out);
  }
}
