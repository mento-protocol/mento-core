// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { ILiquidityPolicy } from "./Interfaces/ILiquidityPolicy.sol";

/**
 * @title ReservePolicy
 * @notice Policy that determines rebalance actions using the Reserve as liquidity source.
 */
contract ReservePolicy is ILiquidityPolicy {
  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  function name() external pure returns (string memory) {
    return "ReservePolicy";
  }

  /* ============================================================ */
  /* ================== External Functions ====================== */
  /* ============================================================ */

  /**
   * @notice Determine how the policy should act and return the action to take
   * @param ctx The current pool context
   * @return shouldAct True if policy should take action
   * @return action The action to execute
   */
  function determineAction(LQ.Context memory ctx) external pure returns (bool shouldAct, LQ.Action memory action) {
    LQ.Direction direction = ctx.prices.poolPriceAbove ? LQ.Direction.Expand : LQ.Direction.Contract;

    if (direction == LQ.Direction.Expand) {
      return _handleExpansion(ctx);
    } else {
      return _handleContraction(ctx);
    }
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Handle expansion case (pool price > oracle price)
   * @dev Move collateral OUT of pool, debt tokens IN to pool
   */
  function _handleExpansion(LQ.Context memory ctx) internal pure returns (bool shouldAct, LQ.Action memory action) {
    (uint256 collateralOut18, uint256 debtIn18) = _calculateExpansionAmounts(
      ctx.reserves,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.incentiveBps,
      ctx.isToken0Debt
    );

    // Get decimal factors based on token ordering
    uint256 debtDec = ctx.isToken0Debt ? uint256(ctx.token0Dec) : uint256(ctx.token1Dec);
    uint256 collateralDec = ctx.isToken0Debt ? uint256(ctx.token1Dec) : uint256(ctx.token0Dec);

    // Convert to raw token units
    uint256 collateralOutRaw = LQ.from1e18(collateralOut18, collateralDec);
    uint256 debtInRaw = LQ.from1e18(debtIn18, debtDec);

    // Check if we need to take action
    if (collateralOutRaw == 0 && debtInRaw == 0) {
      return (false, _emptyAction(ctx.pool));
    }

    // Convert to token0/token1 ordering for FPMM
    (uint256 amount0Out, uint256 amount1Out) = LQ.toTokenOrder(
      0, // debtOut is 0 (debt flows INTO pool)
      collateralOutRaw, // collateral flows OUT of pool
      ctx.isToken0Debt
    );

    // Build extra data for strategy callback
    bytes memory cb = abi.encode(LQ.incentiveAmount(debtInRaw, ctx.incentiveBps), ctx.isToken0Debt);

    // Build action
    action = LQ.Action({
      pool: ctx.pool,
      dir: LQ.Direction.Expand,
      liquiditySource: LQ.LiquiditySource.Reserve,
      amount0Out: amount0Out,
      amount1Out: amount1Out,
      inputAmount: debtInRaw, // amount strategy will provide
      incentiveBps: ctx.incentiveBps,
      data: cb
    });

    return (true, action);
  }

  /**
   * @notice Handle contraction case (pool price < oracle price)
   * @dev Move debt tokens OUT of pool, collateral IN to pool
   */
  function _handleContraction(LQ.Context memory ctx) internal pure returns (bool shouldAct, LQ.Action memory action) {
    (uint256 debtOut18, uint256 collateralIn18) = _calculateContractionAmounts(
      ctx.reserves,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.incentiveBps,
      ctx.isToken0Debt
    );

    // Get decimal factors
    uint256 debtDec = ctx.isToken0Debt ? uint256(ctx.token0Dec) : uint256(ctx.token1Dec);
    uint256 collateralDec = ctx.isToken0Debt ? uint256(ctx.token1Dec) : uint256(ctx.token0Dec);

    // Convert to raw token units
    uint256 debtOutRaw = LQ.from1e18(debtOut18, debtDec);
    uint256 collateralInRaw = LQ.from1e18(collateralIn18, collateralDec);

    // Check if we need to take action
    if (debtOutRaw == 0 && collateralInRaw == 0) {
      return (false, _emptyAction(ctx.pool));
    }

    // Convert to token0/token1 ordering for FPMM
    (uint256 amount0Out, uint256 amount1Out) = LQ.toTokenOrder(
      debtOutRaw, // debt flows OUT of pool
      0, // collateralOut is 0 (collateral flows INTO pool)
      ctx.isToken0Debt
    );

    // Build extra data for strategy callback
    bytes memory cb = abi.encode(LQ.incentiveAmount(collateralInRaw, ctx.incentiveBps), ctx.isToken0Debt);

    // Build action
    action = LQ.Action({
      pool: ctx.pool,
      dir: LQ.Direction.Contract,
      liquiditySource: LQ.LiquiditySource.Reserve,
      amount0Out: amount0Out,
      amount1Out: amount1Out,
      inputAmount: collateralInRaw, // amount strategy will provide
      incentiveBps: ctx.incentiveBps,
      data: cb
    });

    return (true, action);
  }

  /**
   * @notice Calculates the amounts for expansion
   * @dev Expansion: move collateral out of the pool and move debt tokens into the pool.
   *      CollateralOut = (CollateralReserve - OraclePrice * DebtReserve) / (1 + 1 - incentive)
   *      DebtIn = CollateralOut / OraclePrice
   * @param reserves The current reserves of the pool,
   * @param oracleNum The numerator of the target price
   * @param oracleDen The denominator of the target price
   * @param incentiveBps The rebalance incentive in basis points
   * @return collateralOut18 The amount of collateral tokens to move out of the pool
   * @return debtIn18 The amount of debt tokens to move into the pool
   */
  function _calculateExpansionAmounts(
    LQ.Reserves memory reserves,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 incentiveBps,
    bool isToken0Debt
  ) internal pure returns (uint256 collateralOut18, uint256 debtIn18) {
    // reserveNum = normalized token1, reserveDen = normalized token0
    // If token0 is debt, then: debt = reserveDen (token0), collateral = reserveNum (token1)
    // If token1 is debt, then: debt = reserveNum (token1), collateral = reserveDen (token0)
    uint256 debt18 = isToken0Debt ? reserves.reserveDen : reserves.reserveNum;
    uint256 collateral18 = isToken0Debt ? reserves.reserveNum : reserves.reserveDen;

    uint256 priceAdjustedDebt = ((debt18 * oracleNum) / oracleDen);

    // Check if expansion is actually feasible
    // If collateral <= debt*oracle_price, pool is balanced/under-collateralized
    // Expansion only makes sense when pool has excess collateral (collateral > debt*oracle_price)
    if (collateral18 <= priceAdjustedDebt) {
      return (0, 0); // No expansion needed as pool doesn't have excess collateral
    }

    uint256 numerator = collateral18 - priceAdjustedDebt;
    uint256 denominator = (LQ.BASIS_POINTS_DENOMINATOR * 2) - incentiveBps;

    collateralOut18 = (numerator * LQ.BASIS_POINTS_DENOMINATOR) / denominator;
    debtIn18 = (collateralOut18 * oracleDen) / oracleNum;
  }

  /**
   * @notice Calculates the amounts for contraction
   * @dev Contraction: move debt tokens out of the pool and move collateral into the pool.
   *      DebtOut = (OraclePrice * DebtReserve - CollateralReserve) / (OraclePrice + OraclePrice * (1 - incentive))
   *      CollateralIn = DebtOut * OraclePrice
   * @param reserves The current reserves of the pool.
   * @param oracleNum The numerator of the target price.
   * @param oracleDen The denominator of the target price.
   * @param incentiveBps The rebalance incentive in basis points.
   * @return debtOut18 The amount of debt tokens to move out of the pool.
   * @return collateralIn18 The amount of collateral tokens to move into the pool.
   */
  function _calculateContractionAmounts(
    LQ.Reserves memory reserves,
    uint256 oracleNum,
    uint256 oracleDen,
    uint256 incentiveBps,
    bool isToken0Debt
  ) internal pure returns (uint256 debtOut18, uint256 collateralIn18) {
    // reserveNum = normalized token1, reserveDen = normalized token0
    // If token0 is debt, then: debt = reserveDen (token0), collateral = reserveNum (token1)
    // If token1 is debt, then: debt = reserveNum (token1), collateral = reserveDen (token0)
    uint256 debt18 = isToken0Debt ? reserves.reserveDen : reserves.reserveNum;
    uint256 collateral18 = isToken0Debt ? reserves.reserveNum : reserves.reserveDen;

    uint256 priceAdjustedDebt = (debt18 * oracleNum) / oracleDen;

    // Check if contraction is actually feasible
    // If debt*oracle_price <= collateral, pool is balanced/over-collateralized
    // Contraction only makes sense when pool has excess debt (debt*oracle_price > collateral)
    if (priceAdjustedDebt <= collateral18) {
      return (0, 0); // No contraction needed
    }

    uint256 numerator = priceAdjustedDebt - collateral18;
    uint256 denominator = (2 * LQ.BASIS_POINTS_DENOMINATOR) - incentiveBps;

    debtOut18 = (numerator * oracleDen * LQ.BASIS_POINTS_DENOMINATOR) / (oracleNum * denominator);
    collateralIn18 = (debtOut18 * oracleNum) / oracleDen;
  }

  /**
   * @notice Create an empty action
   */
  function _emptyAction(address pool) internal pure returns (LQ.Action memory) {
    return
      LQ.Action({
        pool: pool,
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: 0,
        amount1Out: 0,
        inputAmount: 0,
        incentiveBps: 0,
        data: ""
      });
  }
}
