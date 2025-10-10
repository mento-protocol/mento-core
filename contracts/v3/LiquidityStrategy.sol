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

  /* ============================================================ */
  /* ======================= Constructor ======================== */
  /* ============================================================ */

  /**
   * @notice Constructor
   * @param _initialOwner The initial owner of the contract
   */
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
    if (!(incentiveBps <= poolIncentiveCap && incentiveBps <= LQ.BASIS_POINTS_DENOMINATOR)) revert LS_BAD_INCENTIVE();
    poolConfigs[pool].rebalanceIncentive = incentiveBps;
    emit RebalanceIncentiveSet(pool, incentiveBps);
  }

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityStrategy
  function rebalance(address pool) external virtual nonReentrant {
    _ensurePool(pool);
    PoolConfig memory config = poolConfigs[pool];
    if (block.timestamp <= config.lastRebalance + config.rebalanceCooldown) revert LS_COOLDOWN_ACTIVE();

    LQ.Context memory ctx = LQ.newContext(pool, config);
    LQ.Action memory action = _determineAction(ctx);

    (address debtToken, address collateralToken) = ctx.tokens();

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: action.inputAmount,
        incentiveBps: ctx.incentiveBps,
        dir: action.dir,
        isToken0Debt: ctx.isToken0Debt,
        debtToken: debtToken,
        collateralToken: collateralToken
      })
    );

    IFPMM(ctx.pool).rebalance(action.amount0Out, action.amount1Out, hookData);

    uint256 incentiveAmount = LQ.incentiveAmount(action.inputAmount, ctx.incentiveBps);
    emit LiquidityMoved(
      ctx.pool,
      action.dir,
      action.inputAmount,
      action.amount0Out + action.amount1Out,
      incentiveAmount
    );

    poolConfigs[pool].lastRebalance = uint64(block.timestamp);
    (, , , , uint256 diffAfter, ) = IFPMM(pool).getPrices();
    emit RebalanceExecuted(pool, ctx.prices.diffBps, diffAfter);
  }

  /**
   * @notice Hook called by FPMM during rebalance to handle token transfers
   * @dev Virtual function that can be overridden for custom callback handling
   * @param sender The address that initiated the rebalance (must be this contract)
   * @param amount0Out The amount of token0 to be sent from the pool
   * @param amount1Out The amount of token1 to be sent from the pool
   * @param data Encoded callback data containing rebalance parameters
   */
  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external virtual {
    address pool = msg.sender;
    _ensurePool(pool);
    if (sender != address(this)) revert LS_INVALID_SENDER();

    LQ.CallbackData memory cb = abi.decode(data, (LQ.CallbackData));
    _handleCallback(pool, amount0Out, amount1Out, cb);
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

  /**
   * @notice Determines the rebalance action for a pool by building context and calculating action
   * @dev Useful for external callers to preview actions and for testing
   * @param pool The address of the pool to check
   * @return ctx The liquidity context containing pool state
   * @return action The determined rebalance action
   */
  function determineAction(address pool) external view returns (LQ.Context memory ctx, LQ.Action memory action) {
    _ensurePool(pool);
    PoolConfig memory config = poolConfigs[pool];
    ctx = LQ.newContext(pool, config);
    action = _determineAction(ctx);
  }

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */
  /**
   * @notice Handles the rebalance callback from the FPMM pool
   * @dev Must be implemented by concrete strategies to source liquidity
   * @param pool The address of the FPMM pool
   * @param amount0Out The amount of token0 being sent from the pool
   * @param amount1Out The amount of token1 being sent from the pool
   * @param cb The decoded callback data containing rebalance parameters
   */
  function _handleCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    LQ.CallbackData memory cb
  ) internal virtual;

  /**
   * @notice Clamps expansion amounts based on strategy-specific constraints
   * @dev Override this method to limit expansion based on available liquidity
   *      Default implementation returns ideal amounts unchanged
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtExpanded The calculated ideal amount of debt tokens to add to pool
   * @param idealCollateralPayed The calculated ideal amount of collateral to receive from pool
   * @return debtExpanded The actual debt amount to expand (may be less than ideal)
   * @return collateralPayed The actual collateral amount to receive (adjusted proportionally)
   */
  function _clampExpansion(
    LQ.Context memory ctx,
    uint256 idealDebtExpanded,
    uint256 idealCollateralPayed
  ) internal view virtual returns (uint256 debtExpanded, uint256 collateralPayed) {
    return (idealDebtExpanded, idealCollateralPayed);
  }

  /**
   * @notice Clamps contraction amounts based on strategy-specific constraints
   * @dev Override this method to limit contraction based on available collateral
   *      Default implementation returns ideal amounts unchanged
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtContracted The calculated ideal amount of debt tokens to receive from pool
   * @param idealCollateralReceived The calculated ideal amount of collateral to add to pool
   * @return debtContracted The actual debt amount to contract (may be less than ideal)
   * @return collateralReceived The actual collateral amount to send (adjusted proportionally)
   */
  function _clampContraction(
    LQ.Context memory ctx,
    uint256 idealDebtContracted,
    uint256 idealCollateralReceived
  ) internal view virtual returns (uint256 debtContracted, uint256 collateralReceived) {
    return (idealDebtContracted, idealCollateralReceived);
  }

  /* ============================================================ */
  /* ==================== Internal Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Adds a new pool to the strategy's registry
   * @dev Virtual function to allow strategies to extend with additional logic
   * @param pool The address of the FPMM pool to add
   * @param debtToken The address of the debt token (determines isToken0Debt)
   * @param cooldown The cooldown period between rebalances in seconds
   * @param incentiveBps The rebalance incentive in basis points
   */
  function _addPool(address pool, address debtToken, uint64 cooldown, uint32 incentiveBps) internal virtual {
    if (pool == address(0)) revert LS_POOL_MUST_BE_SET();
    // Verify incentive
    uint256 poolCap = IFPMM(pool).rebalanceIncentive();
    if (!(incentiveBps <= LQ.BASIS_POINTS_DENOMINATOR && incentiveBps <= poolCap)) revert LS_BAD_INCENTIVE();
    if (!pools.add(pool)) revert LS_POOL_ALREADY_EXISTS(); // Ensure pool is added
    bool isToken0Debt = debtToken == IFPMM(pool).token0();

    poolConfigs[pool] = PoolConfig({
      isToken0Debt: isToken0Debt,
      lastRebalance: 0,
      rebalanceCooldown: cooldown,
      rebalanceIncentive: incentiveBps
    });

    emit PoolAdded(pool, isToken0Debt, cooldown, incentiveBps);
  }

  /**
   * @notice Removes a pool from the strategy's registry
   * @dev Virtual function to allow strategies to extend with cleanup logic
   * @param pool The address of the pool to remove
   */
  function _removePool(address pool) internal virtual {
    if (!pools.remove(pool)) revert LS_POOL_NOT_FOUND();
    delete poolConfigs[pool];
    emit PoolRemoved(pool);
  }

  /**
   * @notice Ensures that a pool is registered in the strategy
   * @dev Virtual function to allow custom pool validation logic
   * @param pool The address of the pool to check
   */
  function _ensurePool(address pool) internal view {
    if (!pools.contains(pool)) revert LS_POOL_NOT_FOUND();
  }

  /**
   * @notice Determines the appropriate rebalance action based on pool and oracle prices
   * @dev Reverts if no action is needed
   * @param ctx The liquidity context containing pool state and configuration
   * @return action The rebalance action to execute
   */
  function _determineAction(LQ.Context memory ctx) internal view returns (LQ.Action memory action) {
    if (ctx.prices.poolPriceAbove) {
      return _handlePoolPriceAbove(ctx);
    } else {
      return _handlePoolPriceBelow(ctx);
    }
  }

  /**
   * @notice Handles the case when pool price is above oracle price
   * @dev Calculates expansion or contraction amounts based on token order
   * @param ctx The liquidity context containing pool state and configuration
   * @return action The constructed rebalance action
   */
  function _handlePoolPriceAbove(LQ.Context memory ctx) internal view returns (LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleDen * ctx.reserves.reserveNum - ctx.prices.oracleNum * ctx.reserves.reserveDen;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1OutRaw = numerator / denominator;
    uint256 token1Out = LQ.scaleFromTo(token1OutRaw, 1e18, ctx.token1Dec);
    uint256 token0InRaw = (token1Out * ctx.prices.oracleDen) / ctx.prices.oracleNum;

    uint256 token0In = LQ.scaleFromTo(token0InRaw, ctx.token1Dec, ctx.token0Dec);

    if (ctx.isToken0Debt) {
      // ON/OD < RN/RD => Pool price > Oracle price
      // Expansion: add debt (token0) to pool, take collateral (token1) from pool
      return _buildExpansionAction(ctx, token0In, token1Out);
    } else {
      // ON/OD < RN/RD => Pool price > Oracle price
      // Contraction: take debt (token1) from pool, add collateral (token0) to pool
      return _buildContractionAction(ctx, token1Out, token0In);
    }
  }

  /**
   * @notice Handles the case when pool price is below oracle price
   * @dev Calculates contraction or expansion amounts based on token order
   * @param ctx The liquidity context containing pool state and configuration
   * @return action The constructed rebalance action
   */
  function _handlePoolPriceBelow(LQ.Context memory ctx) internal view returns (LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleNum * ctx.reserves.reserveDen - ctx.prices.oracleDen * ctx.reserves.reserveNum;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1InRaw = numerator / denominator;
    uint256 token1In = LQ.scaleFromTo(token1InRaw, 1e18, ctx.token1Dec);

    uint256 token0OutRaw = (token1In * ctx.prices.oracleDen) / ctx.prices.oracleNum;
    uint256 token0Out = LQ.scaleFromTo(token0OutRaw, ctx.token1Dec, ctx.token0Dec);

    if (ctx.isToken0Debt) {
      // ON/OD > RN/RD => Pool price < Oracle price
      // Contraction: take debt (token0) from pool, add collateral (token1) to pool
      return _buildContractionAction(ctx, token0Out, token1In);
    } else {
      // ON/OD > RN/RD => Pool price < Oracle price
      // Expansion: add debt (token1) to pool, take collateral (token0) from pool
      return _buildExpansionAction(ctx, token1In, token0Out);
    }
  }

  /**
   * @notice Builds an expansion action when pool price is above oracle price
   * @dev Must be implemented by concrete strategies to define how to handle liquidity constraints
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtExpanded The amount of debt tokens to add to the pool
   * @param idealCollateralPayed The amount of collateral tokens to receive from the pool
   * @return action The constructed expansion action
   */
  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 idealDebtExpanded,
    uint256 idealCollateralPayed
  ) internal view returns (LQ.Action memory action) {
    (uint256 debtExpanded, uint256 collateralPayed) = _clampExpansion(ctx, idealDebtExpanded, idealCollateralPayed);

    return ctx.newExpansion(debtExpanded, collateralPayed);
  }

  /**
   * @notice Builds a contraction action when pool price is below oracle price
   * @dev Must be implemented by concrete strategies to define how to handle liquidity constraints
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtContracted The amount of debt tokens to receive from the pool
   * @param idealCollateralReceived The amount of collateral tokens to add to the pool
   * @return action The constructed contraction action
   */
  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 idealDebtContracted,
    uint256 idealCollateralReceived
  ) internal view returns (LQ.Action memory action) {
    (uint256 debtContracted, uint256 collateralReceived) = _clampContraction(
      ctx,
      idealDebtContracted,
      idealCollateralReceived
    );

    return ctx.newContraction(debtContracted, collateralReceived);
  }
}
