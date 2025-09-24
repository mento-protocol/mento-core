// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { EnumerableSetUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IFPMM } from "../interfaces/IFPMM.sol"; // TODO: Confirm location
import { ILiquidityPolicy } from "./Interfaces/ILiquidityPolicy.sol";
import { ILiquidityStrategy } from "./Interfaces/ILiquidityStrategy.sol";
import { ILiquidityController } from "./Interfaces/ILiquidityController.sol";

import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";

/**
 * @title LiquidityController
 * @notice Orchestrates per-pool policy pipelines and executes actions via liquidity source-specific strategies.
 *         Also stores per-pool FPMM config (cooldown, incentive cap, lastRebalance, tokens).
 */
abstract contract LiquidityStrategy is ILiquidityController, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  using SafeERC20 for IERC20Upgradeable;

  /* ============================================================ */
  /* ==================== State Variables ======================= */
  /* ============================================================ */

  EnumerableSetUpgradeable.AddressSet private pools;
  mapping(address => PoolConfig) public poolConfigs;

  /* ============================================================ */
  /* ==================== Initialization ======================== */
  /* ============================================================ */

  function initialize(address owner_) external initializer {
    __Ownable_init();
    __ReentrancyGuard_init();
    transferOwnership(owner_);
  }

  /* ============================================================ */
  /* ================ Admin Functions - Pools =================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityController
  function addPool(
    address pool,
    address debtToken,
    address collateralToken,
    uint64 cooldown,
    uint32 incentiveBps
  ) external onlyOwner {
    require(pool != address(0), "LC: POOL_MUST_BE_SET");
    require(debtToken != address(0) && collateralToken != address(0), "LC: TOKENS_MUST_BE_SET");
    require(debtToken != collateralToken, "LC: TOKENS_MUST_BE_DIFFERENT");

    // Verify LC token ordering matches FPMM ordering
    (address expectedToken0, address expectedToken1) = _orderTokens(debtToken, collateralToken);
    (address actualT0, address actualT1) = IFPMM(pool).tokens();
    require(actualT0 == expectedToken0 && actualT1 == expectedToken1, "LC: FPMM_TOKEN_ORDER_MISMATCH");

    // Verify incentive
    uint256 poolCap = IFPMM(pool).rebalanceIncentive();
    require(incentiveBps <= LQ.BASIS_POINTS_DENOMINATOR && incentiveBps <= poolCap, "LC: BAD_INCENTIVE");
    require(pools.add(pool), "LC: POOL_ALREADY_EXISTS"); // Ensure pool is added

    poolConfigs[pool] = PoolConfig({
      debtToken: debtToken,
      collateralToken: collateralToken,
      lastRebalance: 0,
      rebalanceCooldown: cooldown,
      rebalanceIncentive: incentiveBps
    });

    emit PoolAdded(pool, debtToken, collateralToken, cooldown, incentiveBps);
  }

  /// @inheritdoc ILiquidityController
  function removePool(address pool) external onlyOwner {
    require(pools.remove(pool), "LC: POOL_NOT_FOUND");
    delete poolConfigs[pool];
    emit PoolRemoved(pool);
  }

  /// @inheritdoc ILiquidityController
  function setRebalanceCooldown(address pool, uint64 cooldown) external onlyOwner {
    _ensurePool(pool);
    poolConfigs[pool].rebalanceCooldown = cooldown;
    emit RebalanceCooldownSet(pool, cooldown);
  }

  /// @inheritdoc ILiquidityController
  function setRebalanceIncentive(address pool, uint32 incentiveBps) external onlyOwner {
    _ensurePool(pool);
    uint256 poolIncentiveCap = IFPMM(pool).rebalanceIncentive();
    require(incentiveBps <= poolIncentiveCap && incentiveBps <= LQ.BASIS_POINTS_DENOMINATOR, "LC: BAD_INCENTIVE");
    poolConfigs[pool].rebalanceIncentive = incentiveBps;
    emit RebalanceIncentiveSet(pool, incentiveBps);
  }

  /* ============================================================ */
  /* ==================== Abstract Functions ==================== */
  /* ============================================================ */

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

  function _execute(LQ.Action memory action) internal virtual returns (bool);

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityController
  function rebalance(address pool) external nonReentrant {
    _ensurePool(pool);

    PoolConfig memory config = poolConfigs[pool];
    require(block.timestamp > config.lastRebalance + config.rebalanceCooldown, "LC: COOLDOWN_ACTIVE");

    (LQ.Context memory ctx, bool inRange, uint256 diffBefore) = _readCtx(pool, config);
    require(!inRange, "LC: POOL_PRICE_IN_RANGE");

    bool acted = false;

    (bool shouldAct, LQ.Action memory action) = _determineAction(ctx);

    if (shouldAct) {
      bool ok = _execute(action);
      require(ok, "LC: STRATEGY_EXECUTION_FAILED");
      acted = true;
      // refresh after action execution, stop early if price in range
      (ctx, inRange, ) = _readCtx(pool, config);
    }

    require(acted, "LC: NO_ACTION_TAKEN");

    poolConfigs[pool].lastRebalance = uint128(block.timestamp);
    (, , , , uint256 diffAfter, ) = IFPMM(pool).getPrices();
    emit RebalanceExecuted(pool, diffBefore, diffAfter);
  }

  /* ============================================================ */
  /* ==================== View Functions ======================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityController
  function isPoolRegistered(address pool) public view returns (bool) {
    return pools.contains(pool);
  }

  /// @inheritdoc ILiquidityController
  function getPools() external view returns (address[] memory) {
    return pools.values();
  }

  /* ============================================================ */
  /* ==================== Internal Functions ==================== */
  /* ============================================================ */

  function _ensurePool(address pool) internal view {
    require(pools.contains(pool), "LC: POOL_NOT_FOUND");
  }

  /// @dev Build policy context, calculate range status, and return current deviation.
  function _readCtx(
    address pool,
    PoolConfig memory config
  ) internal view returns (LQ.Context memory ctx, bool priceInRange, uint256 priceDiffBps) {
    // Build context with all data
    (ctx) = _buildFullContext(pool, config);

    // Check if price in range
    priceDiffBps = ctx.prices.diffBps;
    priceInRange = _checkInRange(ctx.prices, pool);
  }

  /// @dev Build full context combining all data needed for rebalancing
  function _buildFullContext(address pool, PoolConfig memory config) internal view returns (LQ.Context memory ctx) {
    IFPMM fpmm = IFPMM(pool);
    ctx.pool = pool;

    // Get and set token data
    {
      (uint256 dec0, uint256 dec1, , , address t0, address t1) = fpmm.metadata();
      _validateDecimals(dec0, dec1);

      ctx.token0 = t0;
      ctx.token1 = t1;
      ctx.token0Dec = uint64(dec0);
      ctx.token1Dec = uint64(dec1);
      ctx.isToken0Debt = config.debtToken == t0;

      // Set incentive
      uint256 fpmmIncentive = fpmm.rebalanceIncentive();
      ctx.incentiveBps = uint128(config.rebalanceIncentive < fpmmIncentive ? config.rebalanceIncentive : fpmmIncentive);
    }

    // Get and set price data
    {
      (
        uint256 oracleNum,
        uint256 oracleDen,
        uint256 reserveNum,
        uint256 reserveDen,
        uint256 diffBps,
        bool poolAbove
      ) = fpmm.getPrices();

      require(oracleNum > 0 && oracleDen > 0, "LC: INVALID_PRICES");

      ctx.reserves = LQ.Reserves({ reserveNum: reserveNum, reserveDen: reserveDen });
      ctx.prices = LQ.Prices({
        oracleNum: oracleNum,
        oracleDen: oracleDen,
        poolPriceAbove: poolAbove,
        diffBps: diffBps
      });
    }
  }

  /// @dev Fetch rebalance thresholds from FPMM
  function _getThresholds(address pool) internal view returns (uint256 upperThreshold, uint256 lowerThreshold) {
    IFPMM fpmm = IFPMM(pool);
    upperThreshold = fpmm.rebalanceThresholdAbove();
    lowerThreshold = fpmm.rebalanceThresholdBelow();
  }

  /// @dev Validate decimal are in valid range
  function _validateDecimals(uint256 dec0, uint256 dec1) internal pure {
    require(dec0 > 0 && dec1 > 0, "LC: ZERO_DECIMALS");
    require(dec0 <= 1e18 && dec1 <= 1e18, "LC: INVALID_DECIMALS");
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
      "LC: INVALID_THRESHOLD"
    );
  }

  /// @dev Order tokens based on size
  function _orderTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
    (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
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

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

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
    } else {
      // ON/OD < RN/RD
      // ON/OD < DebtR/CollR
      action = _buildContractionAction(ctx, token0In, token1Out);
    }
    // TODO: add what need to go here
    return (true, action);
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
    } else {
      // ON/OD > RN/RD
      // ON/OD > DebtR/CollR
      action = _buildExpansionAction(ctx, token1In, token0Out);
    }

    return (true, action);
  }
}
