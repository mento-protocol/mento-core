// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { ReserveRebalancer } from "./ReserveRebalancer.sol";
import { ReservePolicy } from "./ReservePolicy.sol";

contract ReserveLiquidityStrategy is LiquidityStrategy, ReserveRebalancer, ReservePolicy {
  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override returns (LQ.Action memory action) {
    return ReservePolicy._buildExpansionAction(ctx, amountIn, amountOut);
  }

  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override returns (LQ.Action memory action) {
    return ReservePolicy._buildContractionAction(ctx, amountIn, amountOut);
  }

  function _execute(LQ.Action memory action) internal override returns (bool) {
    ReserveRebalanceOperator._execute(action);
  }
}
