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

  /**
   * @notice Manually clears transient storage for a pool (for testing only)
   * @dev Simulates the automatic clearing that happens between transactions
   * @param pool The pool address to clear transient storage for
   */
  function clearTransientStorage(address pool) external {
    bytes32 key = bytes32(uint256(uint160(pool)));
    assembly {
      tstore(key, 0)
    }
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
    uint256 idealDebtToExpand,
    uint256 idealCollateralToPay
  ) internal view override returns (uint256 debtToExpand, uint256 collateralToPay) {
    // Apply test limits if configured
    if (shouldLimitExpansion && idealDebtToExpand > maxExpansionAmount) {
      debtToExpand = maxExpansionAmount;
      collateralToPay = ctx.convertToCollateralWithFee(debtToExpand);
    } else {
      debtToExpand = idealDebtToExpand;
      collateralToPay = idealCollateralToPay;
    }

    return (debtToExpand, collateralToPay);
  }

  function _clampContraction(
    LQ.Context memory ctx,
    uint256 idealDebtToContract,
    uint256 idealCollateralToReceive
  ) internal view override returns (uint256 debtToContract, uint256 collateralToReceive) {
    // Apply test limits if configured
    if (shouldLimitContraction && idealDebtToContract > maxContractionAmount) {
      debtToContract = maxContractionAmount;
      collateralToReceive = ctx.convertToDebtToken(debtToContract);
    } else {
      debtToContract = idealDebtToContract;
      collateralToReceive = idealCollateralToReceive;
    }

    return (debtToContract, collateralToReceive);
  }

  function _handleCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    LQ.CallbackData memory cb
  ) internal override {
    // Simple test implementation - just verify the callback was called
    // In real implementations, this would handle token transfers

    // For testing purposes, we just verify that at least one amount is being moved
    require(amount0Out > 0 || amount1Out > 0 || cb.inputAmount > 0, "LiquidityStrategyHarness: No amounts");
  }
}
