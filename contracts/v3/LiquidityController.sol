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
contract LiquidityController is ILiquidityController, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  using SafeERC20 for IERC20Upgradeable;

  /* ============================================================ */
  /* ==================== State Variables ======================= */
  /* ============================================================ */

  EnumerableSetUpgradeable.AddressSet private pools;
  mapping(address => PoolConfig) public poolConfigs;

  // Pool -> ordered policy pipeline (e.g., [ReservePolicy, CDPPolicy] || [ReservePolicy])
  mapping(address => ILiquidityPolicy[]) public pipelines;

  // LiquiditySource → Strategy. Links a policy to its execution strategy.
  mapping(LQ.LiquiditySource => ILiquidityStrategy) public strategies;

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
    (, , , , address actualT0, address actualT1) = IFPMM(pool).metadata();
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
    delete pipelines[pool];
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
  /* ======== Admin Functions - Pipelines  & Strategies ========= */
  /* ============================================================ */

  /// @inheritdoc ILiquidityController
  function setPoolPipeline(address pool, ILiquidityPolicy[] calldata policies) external onlyOwner {
    _ensurePool(pool);
    delete pipelines[pool];
    address[] memory policyAddresses = new address[](policies.length);
    for (uint256 i = 0; i < policies.length; i++) {
      pipelines[pool].push(policies[i]);
      policyAddresses[i] = address(policies[i]);
    }
    emit PipelineSet(pool, policyAddresses);
  }

  /// @inheritdoc ILiquidityController
  function setLiquiditySourceStrategy(LQ.LiquiditySource source, ILiquidityStrategy strategy) external onlyOwner {
    require(address(strategy) != address(0), "LC: STRATEGY_ADDRESS_IS_ZERO");
    strategies[source] = strategy;
    emit StrategySet(source, address(strategy));
  }

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityController
  function rebalance(address pool) external nonReentrant {
    _ensurePool(pool);

    PoolConfig memory config = poolConfigs[pool];
    require(block.timestamp > config.lastRebalance + config.rebalanceCooldown, "LC: COOLDOWN_ACTIVE");

    (LQ.Context memory ctx, bool inRange, uint256 diffBefore, bool isToken0Debt) = _readCtx(pool, config);
    require(!inRange, "LC: POOL_PRICE_IN_RANGE");

    ILiquidityPolicy[] memory policies = pipelines[pool];
    require(policies.length > 0, "LC: NO_POLICIES_IN_PIPELINE");

    bool acted = false;

    for (uint256 i = 0; i < policies.length; i++) {
      (bool shouldAct, LQ.Action memory action) = policies[i].determineAction(ctx);
      if (!shouldAct) continue;

      ILiquidityStrategy strategy = strategies[action.liquiditySource];
      require(address(strategy) != address(0), "LC: NO_STRATEGY_FOR_LIQUIDITY_SOURCE");

      uint256 incentiveAmount = LQ.incentiveAmount(action.inputAmount, action.incentiveBps);
      bytes memory cb = LQ.encodeCallback(
        LQ.CallbackData({
          inputAmount: action.inputAmount,
          dir: action.dir,
          incentiveAmount: incentiveAmount,
          liquiditySource: action.liquiditySource,
          isToken0Debt: isToken0Debt,
          extra: bytes("")
        })
      );

      bool ok = strategy.execute(action, cb);
      require(ok, "LC: STRATEGY_EXECUTION_FAILED");
      acted = true;

      // refresh after action execution, stop early if price in range
      (ctx, inRange, , isToken0Debt) = _readCtx(pool, config);
      if (inRange) break;
    }

    // TODO: Do we want to revert if still out of range after pipeline execution or
    //       is it okay that we tried and may have gotten a little closer ?

    if (acted) {
      poolConfigs[pool].lastRebalance = uint128(block.timestamp);
    }

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
  ) internal view returns (LQ.Context memory ctx, bool inRange, uint256 diffBps, bool isToken0Debt) {
    // Build context with all data including thresholds
    uint256 upperThreshold;
    uint256 lowerThreshold;
    (ctx, isToken0Debt, upperThreshold, lowerThreshold) = _buildFullContext(pool, config);

    // Check if in range
    diffBps = ctx.prices.diffBps;
    inRange = _checkInRange(ctx.prices, upperThreshold, lowerThreshold);
  }

  /// @dev Build full context combining all data needed for rebalancing
  function _buildFullContext(
    address pool,
    PoolConfig memory config
  ) internal view returns (LQ.Context memory ctx, bool isToken0Debt, uint256 upperThreshold, uint256 lowerThreshold) {
    IFPMM fpmm = IFPMM(pool);

    // Get FPMM data
    (uint256 dec0, uint256 dec1, , , , ) = fpmm.metadata();
    (
      uint256 oracleNum,
      uint256 oracleDen,
      uint256 reserveNum,
      uint256 reserveDen,
      uint256 diffBps,
      bool poolAbove
    ) = fpmm.getPrices();
    uint256 fpmmIncentive = fpmm.rebalanceIncentive();
    upperThreshold = fpmm.rebalanceThresholdAbove();
    lowerThreshold = fpmm.rebalanceThresholdBelow();

    // Validate decimals
    _validateDecimals(dec0, dec1);

    // Validate prices
    require(oracleNum > 0 && oracleDen > 0, "LC: INVALID_PRICES");

    // Determine debt token
    isToken0Debt = config.debtToken < config.collateralToken;

    // Build reserves
    if (isToken0Debt) {
      ctx.reserves.debt = reserveDen;
      ctx.reserves.collateral = reserveNum;
    } else {
      ctx.reserves.debt = reserveNum;
      ctx.reserves.collateral = reserveDen;
    }

    // Build context
    ctx.pool = pool;
    ctx.prices = LQ.Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: poolAbove, diffBps: diffBps });

    // Set decimals and tokens
    ctx.decDebt = isToken0Debt ? dec0 : dec1;
    ctx.decCollateral = isToken0Debt ? dec1 : dec0;
    ctx.debtToken = config.debtToken;
    ctx.collateralToken = config.collateralToken;

    // Min of controller & FPMM
    ctx.incentiveBps = config.rebalanceIncentive < fpmmIncentive ? config.rebalanceIncentive : fpmmIncentive;
  }

  /// @dev Validate decimal are in valid range
  function _validateDecimals(uint256 dec0, uint256 dec1) internal pure {
    require(dec0 > 0 && dec1 > 0, "LC: ZERO_DECIMALS");
    require(dec0 <= 1e18 && dec1 <= 1e18, "LC: INVALID_DECIMALS");
  }

  /// @dev Check if price is in range using provided thresholds
  function _checkInRange(
    LQ.Prices memory prices,
    uint256 upperThresholdBps,
    uint256 lowerThresholdBps
  ) internal pure returns (bool) {
    _validateThresholds(upperThresholdBps, lowerThresholdBps);

    // Price is in range if deviation is below the relevant threshold
    uint256 threshold = prices.poolPriceAbove ? upperThresholdBps : lowerThresholdBps;
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
}
