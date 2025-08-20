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
      return _handleExpansion(ctx, ctx.incentiveBps);
    } else {
      return _handleContraction(ctx, ctx.incentiveBps);
    }
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Handle expansion case (pool price > oracle price)
   * @dev Move collateral OUT of pool, debt tokens IN to pool
   */
  function _handleExpansion(
    LQ.Context memory ctx,
    uint256 incentiveBps
  ) internal pure returns (bool shouldAct, LQ.Action memory action) {
    (uint256 collateralOut18, uint256 debtIn18) = _calculateExpansionAmounts(
      ctx.reserves,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      incentiveBps
    );

    // Convert to raw token units
    uint256 collateralOutRaw = LQ.from1e18(collateralOut18, ctx.decCollateral);
    uint256 debtInRaw = LQ.from1e18(debtIn18, ctx.decDebt);

    // Check if we need to take action
    if (collateralOutRaw == 0 && debtInRaw == 0) {
      return (false, _emptyAction(ctx.pool));
    }

    // Build action
    action = LQ.Action({
      pool: ctx.pool,
      dir: LQ.Direction.Expand,
      liquiditySource: LQ.LiquiditySource.Reserve,
      debtOut: 0, // debt flows INTO pool
      collateralOut: collateralOutRaw, // collateral flows OUT of pool
      inputAmount: debtInRaw, // amount strategy will provide
      incentiveBps: incentiveBps,
      data: ""
    });

    return (true, action);
  }

  /**
   * @notice Handle contraction case (pool price < oracle price)
   * @dev Move debt tokens OUT of pool, collateral IN to pool
   */
  function _handleContraction(
    LQ.Context memory ctx,
    uint256 incentiveBps
  ) internal pure returns (bool shouldAct, LQ.Action memory action) {
    (uint256 debtOut18, uint256 collateralIn18) = _calculateContractionAmounts(
      ctx.reserves,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      incentiveBps
    );

    // Convert to raw token units
    uint256 debtOutRaw = LQ.from1e18(debtOut18, ctx.decDebt);
    uint256 collateralInRaw = LQ.from1e18(collateralIn18, ctx.decCollateral);

    // Check if we need to take action
    if (debtOutRaw == 0 && collateralInRaw == 0) {
      return (false, _emptyAction(ctx.pool));
    }

    // Build action
    action = LQ.Action({
      pool: ctx.pool,
      dir: LQ.Direction.Contract,
      liquiditySource: LQ.LiquiditySource.Reserve,
      debtOut: debtOutRaw, // debt flows OUT of pool
      collateralOut: 0, // collateral flows INTO pool
      inputAmount: collateralInRaw, // amount strategy will provide
      incentiveBps: incentiveBps,
      data: ""
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
    uint256 incentiveBps
  ) internal pure returns (uint256 collateralOut18, uint256 debtIn18) {
    uint256 priceAdjustedDebt = ((reserves.debt * oracleNum) / oracleDen);

    // Check if expansion is actually feasible
    // If collateral <= debt*oracle_price, pool is balanced/under-collateralized
    // Expansion only makes sense when pool has excess collateral (collateral > debt*oracle_price)
    if (reserves.collateral <= priceAdjustedDebt) {
      return (0, 0); // No expansion needed as pool doesn't have excess collateral
    }

    uint256 numerator = reserves.collateral - priceAdjustedDebt;
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
    uint256 incentiveBps
  ) internal pure returns (uint256 debtOut18, uint256 collateralIn18) {
    uint256 priceAdjustedDebt = (reserves.debt * oracleNum) / oracleDen;

    // Check if contraction is actually feasible
    // If debt*oracle_price <= collateral, pool is balanced/over-collateralized
    // Contraction only makes sense when pool has excess debt (debt*oracle_price > collateral)
    if (priceAdjustedDebt <= reserves.collateral) {
      return (0, 0); // No contraction needed
    }

    uint256 numerator = priceAdjustedDebt - reserves.collateral;
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
        debtOut: 0,
        collateralOut: 0,
        inputAmount: 0,
        incentiveBps: 0,
        data: ""
      });
  }
}
