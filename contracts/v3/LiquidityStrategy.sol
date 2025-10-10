// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;
// solhint-disable max-line-length

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "openzeppelin-contracts-next/contracts/security/ReentrancyGuard.sol";
import { EnumerableSet } from "openzeppelin-contracts-next/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IFPMM } from "../interfaces/IFPMM.sol"; // TODO: Confirm location
import { ILiquidityStrategy } from "./interfaces/ILiquidityStrategy.sol";

import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";

/**
 * @title LiquidityStrategy
 * @notice Base liquidity strategy which determines the current state of the pool in contrast
 * to the oracle price and defers to concrete implementations that handle building and
 * executing the rebalance action.
 */
abstract contract LiquidityStrategy is ILiquidityStrategy, Ownable, ReentrancyGuard {
  using LQ for LQ.Context;
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeERC20 for IERC20;

  /* ============================================================ */
  /* ==================== State Variables ======================= */
  /* ============================================================ */

  EnumerableSet.AddressSet private pools;
  mapping(address => PoolConfig) private poolConfigs;

  /// @notice Constructor
  /// @param _initialOwner the initial owner of the contract
  constructor(address _initialOwner) Ownable() ReentrancyGuard() {
    _transferOwnership(_initialOwner);
  }

  /* ============================================================ */
  /* ================ Admin Functions - Pools =================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityStrategy
  function setRebalanceCooldown(address pool, uint64 cooldown) external onlyOwner {
    _ensurePool(pool);
    poolConfigs[pool].rebalanceCooldown = cooldown;
    emit RebalanceCooldownSet(pool, cooldown);
  }

  /// @inheritdoc ILiquidityStrategy
  function setRebalanceIncentive(address pool, uint32 incentiveBps) external onlyOwner {
    _ensurePool(pool);
    uint256 poolIncentiveCap = IFPMM(pool).rebalanceIncentive();
    require(incentiveBps <= poolIncentiveCap && incentiveBps <= LQ.BASIS_POINTS_DENOMINATOR, "LS: BAD_INCENTIVE");
    poolConfigs[pool].rebalanceIncentive = incentiveBps;
    emit RebalanceIncentiveSet(pool, incentiveBps);
  }

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view virtual returns (LQ.Action memory action);

  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view virtual returns (LQ.Action memory action);

  function _execute(LQ.Context memory ctx, LQ.Action memory action) internal virtual returns (bool);

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityStrategy
  function rebalance(address pool) external nonReentrant {
    _ensurePool(pool);

    PoolConfig memory config = poolConfigs[pool];
    require(block.timestamp > config.lastRebalance + config.rebalanceCooldown, "LS: COOLDOWN_ACTIVE");
    LQ.Context memory ctx = LQ.newContext(pool, config);
    (bool shouldAct, LQ.Action memory action) = _determineAction(ctx);
    require(shouldAct, "LS: NO_ACTION_NEEDED");

    bool ok = _execute(ctx, action);
    require(ok, "LS: STRATEGY_EXECUTION_FAILED");

    poolConfigs[pool].lastRebalance = uint64(block.timestamp);
    (, , , , uint256 diffAfter, ) = IFPMM(pool).getPrices();
    emit RebalanceExecuted(pool, ctx.prices.diffBps, diffAfter);
  }

  /* ============================================================ */
  /* ==================== View Functions ======================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityStrategy
  function isPoolRegistered(address pool) public view returns (bool) {
    return pools.contains(pool);
  }

  /// @inheritdoc ILiquidityStrategy
  function getPools() external view returns (address[] memory) {
    return pools.values();
  }

  /* ============================================================ */
  /* ==================== Internal Functions ==================== */
  /* ============================================================ */

  function _addPool(
    address pool,
    address debtToken,
    uint64 cooldown,
    uint32 incentiveBps
  ) internal virtual {
    require(pool != address(0), "LS: POOL_MUST_BE_SET");
    // Verify incentive
    uint256 poolCap = IFPMM(pool).rebalanceIncentive();
    require(incentiveBps <= LQ.BASIS_POINTS_DENOMINATOR && incentiveBps <= poolCap, "LS: BAD_INCENTIVE");
    require(pools.add(pool), "LS: POOL_ALREADY_EXISTS"); // Ensure pool is added
    bool isToken0Debt = debtToken == IFPMM(pool).token0();

    poolConfigs[pool] = PoolConfig({
      isToken0Debt: isToken0Debt,
      lastRebalance: 0,
      rebalanceCooldown: cooldown,
      rebalanceIncentive: incentiveBps
    });

    emit PoolAdded(pool, isToken0Debt, cooldown, incentiveBps);
  }

  function _removePool(address pool) internal virtual {
    require(pools.remove(pool), "LS: POOL_NOT_FOUND");
    delete poolConfigs[pool];
    emit PoolRemoved(pool);
  }

  function _ensurePool(address pool) internal view virtual {
    require(pools.contains(pool), "LS: POOL_NOT_FOUND");
  }

  /// @dev Fetch rebalance thresholds from FPMM
  function _getThresholds(address pool) internal view returns (uint256 upperThreshold, uint256 lowerThreshold) {
    IFPMM fpmm = IFPMM(pool);
    upperThreshold = fpmm.rebalanceThresholdAbove();
    lowerThreshold = fpmm.rebalanceThresholdBelow();
  }

  /// @dev Check if price is in range using provided thresholds
  function _checkInRange(LQ.Prices memory prices, address pool) internal view returns (bool) {
    (uint256 upperThreshold, uint256 lowerThreshold) = _getThresholds(pool);
    _validateThresholds(upperThreshold, lowerThreshold);

    // Price is in range if deviation is below the relevant threshold
    uint256 threshold = prices.poolPriceAbove ? upperThreshold : lowerThreshold;
    return prices.diffBps < threshold;
  }

  /// @dev Validate threshold values are in acceptable range
  function _validateThresholds(uint256 upperBps, uint256 lowerBps) internal pure {
    require(
      upperBps > 0 &&
        upperBps <= LQ.BASIS_POINTS_DENOMINATOR &&
        lowerBps > 0 &&
        lowerBps <= LQ.BASIS_POINTS_DENOMINATOR,
      "LS: INVALID_THRESHOLD"
    );
  }

  /* ============================================================ */
  /* ================= Internal Policy Functions ================ */
  /* ============================================================ */

  function _determineAction(LQ.Context memory ctx) internal view returns (bool shouldAct, LQ.Action memory action) {
    if (ctx.prices.poolPriceAbove) {
      return _handlePoolPriceAbove(ctx);
    } else {
      return _handlePoolPriceBelow(ctx);
    }
  }

  function _handlePoolPriceAbove(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleDen * ctx.reserves.reserveNum - ctx.prices.oracleNum * ctx.reserves.reserveDen;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1OutRaw = numerator / denominator;
    uint256 token1Out = LQ.scaleFromTo(token1OutRaw, 1e18, ctx.token1Dec);
    uint256 token0InRaw = (token1Out * ctx.prices.oracleDen) / ctx.prices.oracleNum;

    uint256 token0In = LQ.scaleFromTo(token0InRaw, ctx.token1Dec, ctx.token0Dec);

    if (ctx.isToken0Debt) {
      // ON/OD < RN/RD
      // ON/OD < CollR/DebtR
      action = _buildExpansionAction(ctx, token0In, token1Out);
      shouldAct = true;
    } else {
      // ON/OD < RN/RD
      // ON/OD < DebtR/CollR
      action = _buildContractionAction(ctx, token0In, token1Out);
      shouldAct = true;
    }
  }

  function _handlePoolPriceBelow(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleNum * ctx.reserves.reserveDen - ctx.prices.oracleDen * ctx.reserves.reserveNum;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1InRaw = numerator / denominator;
    uint256 token1In = LQ.scaleFromTo(token1InRaw, 1e18, ctx.token1Dec);

    uint256 token0OutRaw = (token1In * ctx.prices.oracleDen) / ctx.prices.oracleNum;
    uint256 token0Out = LQ.scaleFromTo(token0OutRaw, ctx.token1Dec, ctx.token0Dec);

    if (ctx.isToken0Debt) {
      // ON/OD > RN/RD
      // ON/OD > CollR/DebtR
      action = _buildContractionAction(ctx, token1In, token0Out);
      shouldAct = true;
    } else {
      // ON/OD > RN/RD
      // ON/OD > DebtR/CollR
      action = _buildExpansionAction(ctx, token1In, token0Out);
      shouldAct = true;
    }
  }
}
