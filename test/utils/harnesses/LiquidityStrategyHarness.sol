// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityStrategy } from "contracts/v3/LiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

/**
 * @title LiquidityStrategyHarness
 * @notice Concrete implementation of LiquidityStrategy for testing abstract logic
 */
contract LiquidityStrategyHarness is LiquidityStrategy {
  using LQ for LQ.Context;

  // Storage for test configuration
  bool public shouldLimitExpansion;
  uint256 public maxExpansionAmount;
  bool public shouldLimitContraction;
  uint256 public maxContractionAmount;

  constructor(address _initialOwner) LiquidityStrategy(_initialOwner) {}

  /* ============================================================ */
  /* ==================== Test Configuration ==================== */
  /* ============================================================ */

  function setExpansionLimit(uint256 _limit) external {
    shouldLimitExpansion = true;
    maxExpansionAmount = _limit;
  }

  function setContractionLimit(uint256 _limit) external {
    shouldLimitContraction = true;
    maxContractionAmount = _limit;
  }

  function clearLimits() external {
    shouldLimitExpansion = false;
    shouldLimitContraction = false;
  }

  /* ============================================================ */
  /* =============== Public Pool Management Functions =========== */
  /* ============================================================ */

  function addPool(address pool, address debtToken, uint64 cooldown, uint32 incentiveBps) external onlyOwner {
    LiquidityStrategy._addPool(pool, debtToken, cooldown, incentiveBps);
  }

  function removePool(address pool) external onlyOwner {
    LiquidityStrategy._removePool(pool);
  }

  /* ============================================================ */
  /* ============== Virtual Function Implementations ============ */
  /* ============================================================ */

  function _clampExpansion(
    LQ.Context memory ctx,
    uint256 idealDebtExpanded,
    uint256 idealCollateralPayed
  ) internal view override returns (uint256 debtExpanded, uint256 collateralPayed) {
    // Apply test limits if configured
    if (shouldLimitExpansion && idealDebtExpanded > maxExpansionAmount) {
      debtExpanded = maxExpansionAmount;
      collateralPayed = ctx.convertToCollateralWithFee(debtExpanded);
    } else {
      debtExpanded = idealDebtExpanded;
      collateralPayed = idealCollateralPayed;
    }

    return (debtExpanded, collateralPayed);
  }

  function _clampContraction(
    LQ.Context memory ctx,
    uint256 idealDebtContracted,
    uint256 idealCollateralReceived
  ) internal view override returns (uint256 debtContracted, uint256 collateralReceived) {
    // Apply test limits if configured
    if (shouldLimitContraction && idealDebtContracted > maxContractionAmount) {
      debtContracted = maxContractionAmount;
      collateralReceived = ctx.convertToDebtToken(debtContracted);
    } else {
      debtContracted = idealDebtContracted;
      collateralReceived = idealCollateralReceived;
    }

    return (debtContracted, collateralReceived);
  }

  function _handleCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    LQ.CallbackData memory cb
  ) internal override {
    // Simple test implementation - just verify the callback was called
    // In real implementations, this would handle token transfers

    // For testing purposes, we just verify the amounts are correct
    uint256 expectedOut = cb.dir == LQ.Direction.Expand
      ? (cb.isToken0Debt ? amount1Out : amount0Out) // Collateral out
      : (cb.isToken0Debt ? amount0Out : amount1Out); // Debt out

    require(expectedOut > 0, "LiquidityStrategyHarness: Invalid amount out");
  }
}
