// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";

/**
 * @title ReservePolicy
 * @notice Policy that determines rebalance actions using the Reserve as liquidity source.
 */
abstract contract ReservePolicy {
  using LQ for LQ.Context;

  function _getReserve(address pool) internal view virtual returns (address);

  /// add debt token from stabilityPool balance to FPMM
  /// take collateral from FPMM and send to stabilityPool including incentive
  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 debtTokenDelta,
    uint256 collateralTokenDelta
  ) internal view virtual returns (LQ.Action memory action) {
    if (ctx.isToken0Debt) {
      action = LQ.Action({
        pool: ctx.pool,
        dir: LQ.Direction.Expand,
        amount0Out: 0,
        amount1Out: collateralTokenDelta,
        inputAmount: debtTokenDelta
      });
    } else {
      action = LQ.Action({
        pool: ctx.pool,
        dir: LQ.Direction.Expand,
        amount0Out: collateralTokenDelta,
        amount1Out: 0,
        inputAmount: debtTokenDelta
      });
    }

    return action;
  }

  /// take dept token from fpmm for colateral token from stabilityPool/redemptions
  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 collateralTokenDelta,
    uint256 debtTokenDelta
  ) internal view virtual returns (LQ.Action memory action) {
    address collateralToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
    uint256 collateralBalance = IERC20(collateralToken).balanceOf(_getReserve(ctx.pool));

    if (collateralBalance == 0) {
      revert("ReservePolicy: Reserve out of collateral");
    }

    if (collateralBalance < collateralTokenDelta) {
      collateralTokenDelta = collateralBalance;
      debtTokenDelta = ctx.convertToDebtToken(collateralBalance);
    }

    if (ctx.isToken0Debt) {
      action = LQ.Action({
        pool: ctx.pool,
        dir: LQ.Direction.Expand,
        amount0Out: debtTokenDelta,
        amount1Out: 0,
        inputAmount: collateralTokenDelta
      });
    } else {
      action = LQ.Action({
        pool: ctx.pool,
        dir: LQ.Direction.Expand,
        amount0Out: 0,
        amount1Out: debtTokenDelta,
        inputAmount: collateralTokenDelta
      });
    }

    return action;
  }
}
