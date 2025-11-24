// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityStrategy } from "contracts/liquidityStrategies/LiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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

  constructor(address _initialOwner) LiquidityStrategy(false) {
    __initializeHarness(_initialOwner);
  }

  function __initializeHarness(address _initialOwner) private initializer {
    __LiquidityStrategy_init(_initialOwner);
  }

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
    // solhint-disable-next-line no-inline-assembly
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
      collateralToPay = ctx.convertToCollateralWithFee(
        debtToExpand,
        LQ.BASIS_POINTS_DENOMINATOR,
        LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps
      );
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

  // solhint-disable-next-line no-unused-vars
  function _handleCallback(address pool, uint256, uint256, LQ.CallbackData memory cb) internal override {
    // Determine which token goes into the pool
    address tokenIn;

    if (cb.dir == LQ.Direction.Expand) {
      // Expansion: provide debt to pool, receive collateral from pool
      tokenIn = cb.debtToken;
    } else {
      // Contraction: provide collateral to pool, receive debt from pool
      tokenIn = cb.collToken;
    }

    // Transfer tokenIn to the pool
    // Assumes harness has been funded with tokens in test setup
    // Note: incentive stays with strategy, rest goes to pool
    IERC20(tokenIn).transfer(pool, cb.amountOwedToPool);

    // Note: Tokens coming OUT of the pool (amount0Out/amount1Out) have already been
    // transferred to this contract by the FPMM, so no action needed
    // The incentiveAmount is kept by this contract (also already transferred by FPMM)
  }
}
