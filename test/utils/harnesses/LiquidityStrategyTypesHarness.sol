// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { ILiquidityStrategy } from "contracts/interfaces/ILiquidityStrategy.sol";

/**
 * @title LiquidityStrategyTypesHarness
 * @notice Harness contract to expose LiquidityStrategyTypes library functions for testing
 */
contract LiquidityStrategyTypesHarness {
  using LQ for LQ.Context;

  /* ============================================================ */
  /* =================== Context Functions ====================== */
  /* ============================================================ */

  function newRebalanceContext(
    address pool,
    ILiquidityStrategy.PoolConfig memory config
  ) external view returns (LQ.Context memory) {
    return LQ.newRebalanceContext(pool, config);
  }

  function debtToken(LQ.Context memory ctx) external pure returns (address) {
    return ctx.debtToken();
  }

  function collateralToken(LQ.Context memory ctx) external pure returns (address) {
    return ctx.collateralToken();
  }

  function tokens(LQ.Context memory ctx) external pure returns (address, address) {
    return ctx.tokens();
  }

  function decimals(LQ.Context memory ctx) external pure returns (uint64, uint64) {
    return ctx.decimals();
  }

  function debtToCollateralPrice(LQ.Context memory ctx) external pure returns (uint256, uint256) {
    return ctx.debtToCollateralPrice();
  }

  function collateralToDebtPrice(LQ.Context memory ctx) external pure returns (uint256, uint256) {
    return ctx.collateralToDebtPrice();
  }

  /* ============================================================ */
  /* ================= Conversion Functions ===================== */
  /* ============================================================ */

  function convertToDebtToken(LQ.Context memory ctx, uint256 collateralBalance) external pure returns (uint256) {
    return ctx.convertToDebtToken(collateralBalance);
  }

  function convertToDebtWithFee_custom(
    LQ.Context memory ctx,
    uint256 collateralBalance,
    uint256 incentiveNum,
    uint256 incentiveDen
  ) external pure returns (uint256) {
    return ctx.convertToDebtWithFee(collateralBalance, incentiveNum, incentiveDen);
  }

  function convertToCollateralWithFee_custom(
    LQ.Context memory ctx,
    uint256 debtBalance,
    uint256 incentiveNum,
    uint256 incentiveDen
  ) external pure returns (uint256) {
    return ctx.convertToCollateralWithFee(debtBalance, incentiveNum, incentiveDen);
  }

  /* ============================================================ */
  /* =================== Action Functions ======================= */
  /* ============================================================ */

  function newExpansion(
    LQ.Context memory ctx,
    uint256 debtTokenDelta,
    uint256 collateralTokenDelta
  ) external pure returns (LQ.Action memory) {
    return ctx.newExpansion(debtTokenDelta, collateralTokenDelta);
  }

  function newContraction(
    LQ.Context memory ctx,
    uint256 debtTokenDelta,
    uint256 collateralTokenDelta
  ) external pure returns (LQ.Action memory) {
    return ctx.newContraction(debtTokenDelta, collateralTokenDelta);
  }

  /* ============================================================ */
  /* =================== Helper Functions ======================= */
  /* ============================================================ */

  function to1e18(uint256 amount, uint256 tokenDecimalsFactor) external pure returns (uint256) {
    return LQ.to1e18(amount, tokenDecimalsFactor);
  }

  function from1e18(uint256 amount18, uint256 tokenDecimalsFactor) external pure returns (uint256) {
    return LQ.from1e18(amount18, tokenDecimalsFactor);
  }

  function scaleFromTo(uint256 amount, uint256 fromDec, uint256 toDec) external pure returns (uint256) {
    return LQ.scaleFromTo(amount, fromDec, toDec);
  }

  function convertWithRateScaling(
    uint256 amount,
    uint256 fromDec,
    uint256 toDec,
    uint256 oracleNum,
    uint256 oracleDen
  ) external pure returns (uint256) {
    return LQ.convertWithRateScaling(amount, fromDec, toDec, oracleNum, oracleDen);
  }

  function convertWithRateScalingAndFee(
    uint256 amount,
    uint256 fromDec,
    uint256 toDec,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 incentiveNum,
    uint256 incentiveDen
  ) external pure returns (uint256) {
    return LQ.convertWithRateScalingAndFee(amount, fromDec, toDec, oracleNum, oracleDen, incentiveNum, incentiveDen);
  }

  function mulBps(uint256 amount, uint256 bps) external pure returns (uint256) {
    return LQ.mulBps(amount, bps);
  }

  function incentiveAmount(uint256 amount, uint256 incentiveBps) external pure returns (uint256) {
    return LQ.incentiveAmount(amount, incentiveBps);
  }

  /* ============================================================ */
  /* ================= Constant Accessors ======================= */
  /* ============================================================ */

  function BASIS_POINTS_DENOMINATOR() external pure returns (uint256) {
    return LQ.BASIS_POINTS_DENOMINATOR;
  }
}
