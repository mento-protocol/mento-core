// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { CDPRebalancer } from "./CDPRebalancer.sol";
import { CDPPolicy } from "./CDPPolicy.sol";
import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy is LiquidityStrategy, CDPRebalancer, CDPPolicy {
  using LQ for LQ.Context;

  /// @notice Constructor
  /// @param _initialOwner the initial owner of the contract
  constructor(address _initialOwner) LiquidityStrategy(_initialOwner) {}

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  function addPool(
    address pool,
    address debtToken,
    address collateralToken,
    uint64 cooldown,
    uint32 incentiveBps,
    address stabilityPool,
    address collateralRegistry,
    uint256 redemptionBeta
  ) external onlyOwner {
    LiquidityStrategy.addPool(pool, debtToken, collateralToken, cooldown, incentiveBps);
    CDPPolicy.addPool(pool, stabilityPool, collateralRegistry, redemptionBeta);
  }

  function removePool(address pool) public override(LiquidityStrategy, CDPPolicy) onlyOwner {
    LiquidityStrategy.removePool(pool);
    CDPPolicy.removePool(pool);
  }

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  function _ensurePool(address pool) internal view override(LiquidityStrategy, CDPRebalancer, CDPPolicy) {
    LiquidityStrategy._ensurePool(pool);
  }

  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override(LiquidityStrategy, CDPPolicy) returns (LQ.Action memory action) {
    return CDPPolicy._buildExpansionAction(ctx, amountIn, amountOut);
  }

  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override(LiquidityStrategy, CDPPolicy) returns (LQ.Action memory action) {
    return CDPPolicy._buildContractionAction(ctx, amountIn, amountOut);
  }

  function _execute(
    LQ.Context memory ctx,
    LQ.Action memory action
  ) internal override(LiquidityStrategy, CDPRebalancer) returns (bool) {
    return CDPRebalancer._execute(ctx, action);
  }
}
