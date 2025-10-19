// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { IFPMM } from "../interfaces/IFPMM.sol";
import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

/**
 * @title LiquidityStrategyTypes ()
 * @author Mento Labs
 * @notice Shared types and helpers for the Liquidity Controller, Policies & Strategies.
 */
library LiquidityStrategyTypes {
  using Math for uint256;
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
    uint256 amountOwedToPool; // amount to move to pool (post-incentive)
  }

  /// @notice Callback data passed to hook during rebalance
  struct CallbackData {
    uint256 amountOwedToPool;
    uint256 incentiveBps;
    Direction dir;
    bool isToken0Debt;
    address debtToken;
    address collToken;
  }

  /* ============================================================ */
  /* ================== Context Functions ======================= */
  /* ============================================================ */

  /**
   * @notice Creates a new context by fetching pool state from FPMM
   * @dev Validates token decimals and prices, calculates effective incentive
   * @param pool The address of the FPMM pool
   * @param config The pool configuration from the strategy
   * @return ctx The populated context with pool state and configuration
   */
  function newContext(
    address pool,
    ILiquidityStrategy.PoolConfig memory config
  ) internal view returns (Context memory ctx) {
    IFPMM fpmm = IFPMM(pool);
    ctx.pool = pool;
    // Get and set token data
    {
      (uint256 dec0, uint256 dec1, , , address t0, address t1) = fpmm.metadata();
      if (!(dec0 > 0 && dec1 > 0)) revert ILiquidityStrategy.LS_ZERO_DECIMAL();
      if (!(dec0 <= 1e18 && dec1 <= 1e18)) revert ILiquidityStrategy.LS_INVALID_DECIMAL();

      ctx.token0 = t0;
      ctx.token1 = t1;
      ctx.token0Dec = uint64(dec0);
      ctx.token1Dec = uint64(dec1);
      ctx.isToken0Debt = config.isToken0Debt;

      // Set incentive from FPMM
      ctx.incentiveBps = uint128(fpmm.rebalanceIncentive());
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

      if (!(oracleNum > 0 && oracleDen > 0)) revert ILiquidityStrategy.LS_INVALID_PRICES();

      ctx.reserves = Reserves({ reserveNum: reserveNum, reserveDen: reserveDen });
      ctx.prices = Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolAbove, diffBps: diffBps });
    }
  }

  /**
   * @notice Returns the debt token address from context
   * @param ctx The liquidity context
   * @return The address of the debt token (stable asset)
   */
  function debtToken(Context memory ctx) internal pure returns (address) {
    return ctx.isToken0Debt ? ctx.token0 : ctx.token1;
  }

  /**
   * @notice Returns the collateral token address from context
   * @param ctx The liquidity context
   * @return The address of the collateral token
   */
  function collateralToken(Context memory ctx) internal pure returns (address) {
    return ctx.isToken0Debt ? ctx.token1 : ctx.token0;
  }

  /**
   * @notice Returns both token addresses in debt/collateral order
   * @param ctx The liquidity context
   * @return First the debt token address, then the collateral token address
   */
  function tokens(Context memory ctx) internal pure returns (address, address) {
    return ctx.isToken0Debt ? (ctx.token0, ctx.token1) : (ctx.token1, ctx.token0);
  }

  /**
   * @notice Returns token decimals in debt/collateral order
   * @param ctx The liquidity context
   * @return debtDecimals The decimal factor (10**decimals) of the debt token
   * @return collDecimals The decimal factor (10**decimals) of the collateral token
   */
  function decimals(Context memory ctx) internal pure returns (uint64 debtDecimals, uint64 collDecimals) {
    return ctx.isToken0Debt ? (ctx.token0Dec, ctx.token1Dec) : (ctx.token1Dec, ctx.token0Dec);
  }

  /**
   * @notice Returns the oracle price for converting debt to collateral
   * @dev Price convention: Po = ON/OD such that:
   *      - token1 = token0 * ON/OD
   *      - token0 = token1 * OD/ON
   *      For debt→collateral conversion:
   *      - If token0 is debt: collateral = debt * ON/OD
   *      - If token1 is debt: collateral = debt * OD/ON
   * @param ctx The liquidity context
   * @return numerator The price numerator
   * @return denominator The price denominator
   */
  function debtToCollateralPrice(Context memory ctx) internal pure returns (uint256, uint256) {
    return
      ctx.isToken0Debt ? (ctx.prices.oracleNum, ctx.prices.oracleDen) : (ctx.prices.oracleDen, ctx.prices.oracleNum);
  }

  /**
   * @notice Returns the oracle price for converting collateral to debt
   * @dev Price convention: Po = ON/OD such that:
   *      - token1 = token0 * ON/OD
   *      - token0 = token1 * OD/ON
   *      For collateral→debt conversion:
   *      - If token0 is debt: debt = collateral * OD/ON
   *      - If token1 is debt: debt = collateral * ON/OD
   * @param ctx The liquidity context
   * @return numerator The price numerator
   * @return denominator The price denominator
   */
  function collateralToDebtPrice(Context memory ctx) internal pure returns (uint256, uint256) {
    return
      ctx.isToken0Debt ? (ctx.prices.oracleDen, ctx.prices.oracleNum) : (ctx.prices.oracleNum, ctx.prices.oracleDen);
  }

  /**
   * @notice Converts a collateral amount to equivalent debt token amount
   * @dev Uses oracle price and handles decimal scaling
   * @param ctx The liquidity context
   * @param collateralBalance The amount of collateral to convert
   * @return The equivalent amount in debt token units
   */
  function convertToDebtToken(Context memory ctx, uint256 collateralBalance) internal pure returns (uint256) {
    (uint256 priceNumerator, uint256 priceDenominator) = collateralToDebtPrice(ctx);
    (uint256 debtDecimals, uint256 collDecimals) = decimals(ctx);
    return convertWithRateScaling(collateralBalance, collDecimals, debtDecimals, priceNumerator, priceDenominator);
  }

  /**
   * @notice Converts collateral to debt with custom fee parameters
   * @dev Allows specifying custom fee numerator/denominator for flexibility
   * @param ctx The liquidity context
   * @param collateralBalance The amount of collateral to convert
   * @param feeNumerator The fee multiplier numerator
   * @param feeDenominator The fee multiplier denominator
   * @return The equivalent amount in debt token units with fee applied
   */
  function convertToDebtWithFee(
    Context memory ctx,
    uint256 collateralBalance,
    uint256 feeNumerator,
    uint256 feeDenominator
  ) internal pure returns (uint256) {
    (uint256 priceNumerator, uint256 priceDenominator) = collateralToDebtPrice(ctx);
    (uint256 debtDecimals, uint256 collDecimals) = decimals(ctx);
    return
      convertWithRateScalingAndFee(
        collateralBalance,
        collDecimals,
        debtDecimals,
        priceNumerator,
        priceDenominator,
        feeNumerator,
        feeDenominator
      );
  }

  /**
   * @notice Converts debt to collateral with custom fee parameters
   * @dev Allows specifying custom fee numerator/denominator for flexibility
   * @param ctx The liquidity context
   * @param debtBalance The amount of debt tokens to convert
   * @param feeNumerator The fee multiplier numerator
   * @param feeDenominator The fee multiplier denominator
   * @return The equivalent amount in collateral units with fee applied
   */
  function convertToCollateralWithFee(
    Context memory ctx,
    uint256 debtBalance,
    uint256 feeNumerator,
    uint256 feeDenominator
  ) internal pure returns (uint256) {
    (uint256 priceNumerator, uint256 priceDenominator) = debtToCollateralPrice(ctx);
    (uint256 debtDecimals, uint256 collDecimals) = decimals(ctx);
    return
      convertWithRateScalingAndFee(
        debtBalance,
        debtDecimals,
        collDecimals,
        priceNumerator,
        priceDenominator,
        feeNumerator,
        feeDenominator
      );
  }

  /* ============================================================ */
  /* =================== Action Functions ======================= */
  /* ============================================================ */

  /**
   * @notice Creates an expansion action (add debt to pool, receive collateral)
   * @dev Sets amount0Out/amount1Out based on token order
   * @param ctx The liquidity context
   * @param debtToExpand The amount of debt tokens to add to the pool
   * @param collateralToPay The amount of collateral tokens to receive from the pool
   * @return action The constructed expansion action
   */
  function newExpansion(
    Context memory ctx,
    uint256 debtToExpand,
    uint256 collateralToPay
  ) internal pure returns (Action memory action) {
    action.dir = Direction.Expand;
    if (ctx.isToken0Debt) {
      action.amount0Out = 0;
      action.amount1Out = collateralToPay;
    } else {
      action.amount0Out = collateralToPay;
      action.amount1Out = 0;
    }
    action.amountOwedToPool = debtToExpand;
  }

  /**
   * @notice Creates a contraction action (add collateral to pool, receive debt)
   * @dev Sets amount0Out/amount1Out based on token order
   * @param ctx The liquidity context
   * @param debtToContract The amount of debt tokens to receive from the pool
   * @param collateralToReceive The amount of collateral tokens to add to the pool
   * @return action The constructed contraction action
   */
  function newContraction(
    Context memory ctx,
    uint256 debtToContract,
    uint256 collateralToReceive
  ) internal pure returns (Action memory action) {
    action.dir = Direction.Contract;
    if (ctx.isToken0Debt) {
      action.amount0Out = debtToContract;
      action.amount1Out = 0;
    } else {
      action.amount0Out = 0;
      action.amount1Out = debtToContract;
    }
    action.amountOwedToPool = collateralToReceive;
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

  /**
   * @notice Scales an amount from one decimal factor to another
   * @param amount The amount to scale
   * @param fromDec The source decimal factor (10**decimals)
   * @param toDec The target decimal factor (10**decimals)
   * @return The scaled amount
   */
  function scaleFromTo(uint256 amount, uint256 fromDec, uint256 toDec) internal pure returns (uint256) {
    return (amount * toDec) / fromDec;
  }

  /**
   * @notice Scales an amount from one decimal factor to another
   * @param amountNum The amount numerator to scale
   * @param amountDen The amount denominator to scale
   * @param fromDec The source decimal factor (10**decimals)
   * @param toDec The target decimal factor (10**decimals)
   * @return The scaled amount
   */
  function scaleFromTo(
    uint256 amountNum,
    uint256 amountDen,
    uint256 fromDec,
    uint256 toDec
  ) internal pure returns (uint256) {
    return (amountNum * toDec) / (fromDec * amountDen);
  }

  /**
   * @notice Converts an amount with both rate and decimal scaling
   * @dev Formula: (amount * oracleNum * toDec) / (fromDec * oracleDen)
   * @param amount The amount to convert
   * @param fromDec The source decimal factor
   * @param toDec The target decimal factor
   * @param oracleNum The oracle price numerator
   * @param oracleDen The oracle price denominator
   * @return The converted amount
   */
  function convertWithRateScaling(
    uint256 amount,
    uint256 fromDec,
    uint256 toDec,
    uint256 oracleNum,
    uint256 oracleDen
  ) internal pure returns (uint256) {
    return (amount * oracleNum * toDec) / (fromDec * oracleDen);
  }

  /**
   * @notice Converts an amount with rate, decimal scaling, and fee/incentive
   * @dev Formula: (amount * oracleNum * toDec * incentiveNum) / (fromDec * oracleDen * incentiveDen)
   * @param amount The amount to convert
   * @param fromDec The source decimal factor
   * @param toDec The target decimal factor
   * @param oracleNum The oracle price numerator
   * @param oracleDen The oracle price denominator
   * @param incentiveNum The fee/incentive multiplier numerator
   * @param incentiveDen The fee/incentive multiplier denominator
   * @return The converted amount with fee applied
   */
  function convertWithRateScalingAndFee(
    uint256 amount,
    uint256 fromDec,
    uint256 toDec,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 incentiveNum,
    uint256 incentiveDen
  ) internal pure returns (uint256) {
    return (amount * oracleNum).mulDiv(toDec * incentiveNum, fromDec * incentiveDen) / oracleDen;
  }

  /**
   * @notice Multiplies an amount by basis points
   * @param amount The amount to multiply
   * @param bps The basis points (out of 10,000)
   * @return The amount scaled by basis points
   */
  function mulBps(uint256 amount, uint256 bps) internal pure returns (uint256) {
    return (amount * bps) / BASIS_POINTS_DENOMINATOR;
  }

  /**
   * @notice Calculates the incentive amount from an input and incentive rate
   * @param amount The base amount
   * @param incentiveBps The incentive rate in basis points
   * @return The incentive amount
   */
  function incentiveAmount(uint256 amount, uint256 incentiveBps) internal pure returns (uint256) {
    return mulBps(amount, incentiveBps);
  }
}
