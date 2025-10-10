// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { console } from "forge-std/console.sol";
import { IFPMM } from "../../interfaces/IFPMM.sol";
import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";

/**
 * @title LiquidityStrategyTypes ()
 * @author Mento Labs
 * @notice Shared types and helpers for the Liquidity Controller, Policies & Strategies.
 */
library LiquidityStrategyTypes {
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

  /// @notice Read-only context with shared data
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
    Direction dir;
    uint256 amount0Out; // amount of token0 to move out of pool
    uint256 amount1Out; // amount of token1 to move out of pool
    uint256 inputAmount; // amount moved into pool (pre-incentive)
  }

  /* ============================================================ */
  /* ================== Context Functions ======================= */
  /* ============================================================ */

  function newContext(
    address pool,
    ILiquidityStrategy.PoolConfig memory config
  ) internal view returns (Context memory ctx) {
    IFPMM fpmm = IFPMM(pool);
    ctx.pool = pool;
    // Get and set token data
    {
      (uint256 dec0, uint256 dec1, , , address t0, address t1) = fpmm.metadata();
      require(dec0 > 0 && dec1 > 0, "LST: ZERO_DECIMAL");
      require(dec0 <= 1e18 && dec1 <= 1e18, "LST: INVALID_DECIMAL");

      ctx.token0 = t0;
      ctx.token1 = t1;
      ctx.token0Dec = uint64(dec0);
      ctx.token1Dec = uint64(dec1);
      ctx.isToken0Debt = config.isToken0Debt;

      // Set incentive
      uint256 fpmmIncentive = fpmm.rebalanceIncentive();
      ctx.incentiveBps = uint128(config.rebalanceIncentive < fpmmIncentive ? config.rebalanceIncentive : fpmmIncentive);
    }

    // Get and set price data
    {
      (
        uint256 oracleNum,
        uint256 oracleDen,
        uint256 reserveNum,
        uint256 reserveDen,
        uint256 diffBps,
        bool poolAbove
      ) = fpmm.getPrices();

      require(oracleNum > 0 && oracleDen > 0, "LS: INVALID_PRICES");

      ctx.reserves = Reserves({ reserveNum: reserveNum, reserveDen: reserveDen });
      ctx.prices = Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolAbove, diffBps: diffBps });
    }
  }

  function debtToken(Context memory ctx) internal pure returns (address) {
    return ctx.isToken0Debt ? ctx.token0 : ctx.token1;
  }

  function collateralToken(Context memory ctx) internal pure returns (address) {
    return ctx.isToken0Debt ? ctx.token1 : ctx.token0;
  }

  function tokens(Context memory ctx) internal pure returns (address, address) {
    return ctx.isToken0Debt ? (ctx.token0, ctx.token1) : (ctx.token1, ctx.token0);
  }

  function decimals(Context memory ctx) internal pure returns (uint64 debtDecimals, uint64 collDecimals) {
    return ctx.isToken0Debt ? (ctx.token0Dec, ctx.token1Dec) : (ctx.token1Dec, ctx.token0Dec);
  }

  function debtToCollateralPrice(Context memory ctx) internal pure returns (uint256, uint256) {
    return
      ctx.isToken0Debt ? (ctx.prices.oracleDen, ctx.prices.oracleNum) : (ctx.prices.oracleNum, ctx.prices.oracleDen);
  }

  function collateralToDebtPrice(Context memory ctx) internal pure returns (uint256, uint256) {
    return
      ctx.isToken0Debt ? (ctx.prices.oracleNum, ctx.prices.oracleDen) : (ctx.prices.oracleDen, ctx.prices.oracleNum);
  }

  function convertToDebtWithFee(Context memory ctx, uint256 collateralBalance) internal pure returns (uint256) {
    (uint256 priceNumerator, uint256 priceDenominator) = collateralToDebtPrice(ctx);
    (uint256 debtDecimals, uint256 collDecimals) = decimals(ctx);
    return
      convertWithRateScalingAndAddFee(
        collateralBalance,
        collDecimals,
        debtDecimals,
        priceNumerator,
        priceDenominator,
        ctx.incentiveBps + BASIS_POINTS_DENOMINATOR,
        BASIS_POINTS_DENOMINATOR
      );
  }

  function convertToCollateralWithFee(Context memory ctx, uint256 debtBalance) internal pure returns (uint256) {
    (uint256 priceNumerator, uint256 priceDenominator) = debtToCollateralPrice(ctx);
    (uint256 debtDecimals, uint256 collDecimals) = decimals(ctx);
    return
      convertWithRateScalingAndAddFee(
        debtBalance,
        debtDecimals,
        collDecimals,
        priceNumerator,
        priceDenominator,
        BASIS_POINTS_DENOMINATOR,
        BASIS_POINTS_DENOMINATOR - ctx.incentiveBps
      );
  }

  /* ============================================================ */
  /* =================== Action Functions ======================= */
  /* ============================================================ */

  function newExpansion(
    Context memory ctx,
    uint256 expansionAmount,
    uint256 collateralPayed
  ) internal pure returns (Action memory action) {
    action.dir = Direction.Expand;
    if (ctx.isToken0Debt) {
      action.amount0Out = 0;
      action.amount1Out = collateralPayed;
    } else {
      action.amount0Out = collateralPayed;
      action.amount1Out = 0;
    }
    action.inputAmount = expansionAmount;
  }

  function newContraction(
    Context memory ctx,
    uint256 contractionAmount,
    uint256 collateralReceived
  ) internal pure returns (Action memory action) {
    action.dir = Direction.Contract;
    if (ctx.isToken0Debt) {
      action.amount0Out = 0;
      action.amount1Out = contractionAmount;
    } else {
      action.amount0Out = contractionAmount;
      action.amount1Out = 0;
    }
    action.inputAmount = collateralReceived;
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
