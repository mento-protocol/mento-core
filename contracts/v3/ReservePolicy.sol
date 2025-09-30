// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

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
    (uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In) = _calculateRebalanceAmounts(ctx);

    // Check if action is needed
    if (amount0Out == 0 && amount1Out == 0 && amount0In == 0 && amount1In == 0) {
      return (false, _emptyAction(ctx.pool));
    }

    // Determine direction based on debt/collateral flows
    // The direction is determined by what the RESERVE needs to do:
    // Expand: Reserve expands debt supply (provides debt to pool, receives collateral)
    // Contract: Reserve contracts debt supply (receives debt from pool, provides collateral)
    LQ.Direction direction;
    uint256 inputAmount;

    if (ctx.isToken0Debt) {
      // Token0 is debt, Token1 is collateral
      if (amount0In > 0) {
        // Debt flows into pool → Reserve is expanding debt supply
        direction = LQ.Direction.Expand;
        inputAmount = amount0In;
      } else {
        // Debt flows out of pool → Reserve is contracting debt supply
        direction = LQ.Direction.Contract;
        inputAmount = amount1In;
      }
    } else {
      // Token1 is debt, Token0 is collateral
      if (amount1In > 0) {
        // Debt flows into pool → Reserve is expanding debt supply
        direction = LQ.Direction.Expand;
        inputAmount = amount1In;
      } else {
        // Debt flows out of pool → Reserve is contracting debt supply
        direction = LQ.Direction.Contract;
        inputAmount = amount0In;
      }
    }

    bytes memory callbackData = abi.encode(LQ.incentiveAmount(inputAmount, ctx.incentiveBps), ctx.isToken0Debt);

    action = LQ.Action({
      pool: ctx.pool,
      dir: direction,
      liquiditySource: LQ.LiquiditySource.Reserve,
      amount0Out: amount0Out,
      amount1Out: amount1Out,
      inputAmount: inputAmount,
      incentiveBps: ctx.incentiveBps,
      data: callbackData
    });

    return (true, action);
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Calculate rebalance amounts
   * @dev When PP > OP:
   *      - X = (OD * RN - ON * RD) / (OD * (2 - i))
   *      - X = token1 to REMOVE from pool
   *      - Y = X * OD/ON = token0 to ADD to pool
   *
   *      When PP < OP:
   *      - Y = (ON * RD - OD * RN) / (ON * (2 - i))
   *      - Y = token0 to REMOVE from pool
   *      - X = Y * (ON/OD) * (1 - i) = token1 to ADD to pool
   *
   *      The direction depends on which token is debt/collateral:
   *      - If token1 is debt and PP > OP: Contract (remove debt from pool)
   *      - If token1 is collateral and PP > OP: Expand (remove collateral from pool)
   *
   * @param ctx The current pool context with reserves and prices
   * @return amount0Out Amount of token0 to remove from pool
   * @return amount1Out Amount of token1 to remove from pool
   * @return amount0In Amount of token0 to add to pool
   * @return amount1In Amount of token1 to add to pool
   */
  function _calculateRebalanceAmounts(
    LQ.Context memory ctx
  ) internal pure returns (uint256 amount0Out, uint256 amount1Out, uint256 amount0In, uint256 amount1In) {
    uint256 poolPriceNumerator = ctx.reserves.reserveNum * ctx.prices.oracleDen; // RN * OD
    uint256 oraclePriceNumerator = ctx.prices.oracleNum * ctx.reserves.reserveDen; // ON * RD

    // If prices are equal, no rebalancing needed
    if (poolPriceNumerator == oraclePriceNumerator) {
      return (0, 0, 0, 0);
    }

    // OD * (2 - i) for PP > OP case
    uint256 denominator = ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps);

    // Prevent division by zero
    if (denominator == 0) {
      return (0, 0, 0, 0);
    }

    if (poolPriceNumerator > oraclePriceNumerator) {
      // PP > OP: Pool price above oracle (RN/RD > ON/OD)
      // X = (OD * RN - ON * RD) / (OD * (2 - i))
      // X is token1 to REMOVE from pool
      // Y = X * OD/ON is token0 to ADD to pool
      uint256 token1ToRemove18 = ((poolPriceNumerator - oraclePriceNumerator) * LQ.BASIS_POINTS_DENOMINATOR) /
        denominator;
      uint256 token0ToAdd18 = (token1ToRemove18 * ctx.prices.oracleDen) / ctx.prices.oracleNum;

      amount0Out = 0;
      amount1Out = LQ.from1e18(token1ToRemove18, ctx.token1Dec);
      amount0In = LQ.from1e18(token0ToAdd18, ctx.token0Dec);
      amount1In = 0;
    } else {
      // PP < OP: Pool price below oracle (RN/RD < ON/OD)
      // Y = (ON * RD - OD * RN) / (ON * (2 - i))
      // Y is token0 to REMOVE from pool
      // X = Y * (ON/OD) * (1 - i) is token1 to ADD to pool
      uint256 contractionDenominator = ctx.prices.oracleNum * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps);

      // Prevent division by zero
      if (contractionDenominator == 0) {
        return (0, 0, 0, 0);
      }

      uint256 token0ToRemove18 = ((oraclePriceNumerator - poolPriceNumerator) * LQ.BASIS_POINTS_DENOMINATOR) /
        contractionDenominator;
      uint256 token1ToAdd18 = (token0ToRemove18 *
        ctx.prices.oracleNum *
        (LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) / (ctx.prices.oracleDen * LQ.BASIS_POINTS_DENOMINATOR);

      amount0Out = LQ.from1e18(token0ToRemove18, ctx.token0Dec);
      amount1Out = 0;
      amount0In = 0;
      amount1In = LQ.from1e18(token1ToAdd18, ctx.token1Dec);
    }
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
