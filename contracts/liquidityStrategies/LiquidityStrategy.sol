// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
// solhint-disable max-line-length

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { EnumerableSetUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/structs/EnumerableSetUpgradeable.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import { IFPMM } from "../interfaces/IFPMM.sol";
import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "../libraries/LiquidityStrategyTypes.sol";

/**
 * @title LiquidityStrategy
 * @notice Base liquidity strategy which determines the current state of the pool in contrast
 * to the oracle price and defers to concrete implementations that handle building and
 * executing the rebalance action.
 */
abstract contract LiquidityStrategy is
  ILiquidityStrategy,
  Initializable,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable
{
  using LQ for LQ.Context;
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  using SafeERC20 for IERC20;

  uint256 public constant BPS_TO_FEE_SCALER = 1e14;
  uint256 public constant BPS_DENOMINATOR = 10_000;

  /* ============================================================ */
  /* ==================== State Variables ======================= */
  /* ============================================================ */

  EnumerableSetUpgradeable.AddressSet private pools;
  mapping(address => PoolConfig) private poolConfigs;

  /* ============================================================ */
  /* ======================= Constructor ======================== */
  /* ============================================================ */

  /**
   * @notice Disables initializers on implementation contracts.
   * @param disable Set to true to disable initializers (for proxy pattern).
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /**
   * @notice Initializes the LiquidityStrategy contract
   * @param _initialOwner The initial owner of the contract
   */
  // solhint-disable-next-line func-name-mixedcase
  function __LiquidityStrategy_init(address _initialOwner) internal onlyInitializing {
    if (_initialOwner == address(0)) revert LS_INVALID_OWNER();
    __Ownable_init();
    __ReentrancyGuard_init();
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

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc ILiquidityStrategy
  function rebalance(address pool) external virtual nonReentrant {
    _ensurePool(pool);
    if (_getHookCalled(pool)) {
      revert LS_CAN_ONLY_REBALANCE_ONCE(pool);
    }

    PoolConfig memory config = poolConfigs[pool];
    // Skip cooldown check for first rebalance (lastRebalance == 0)
    if (config.lastRebalance > 0 && block.timestamp < config.lastRebalance + config.rebalanceCooldown) {
      revert LS_COOLDOWN_ACTIVE();
    }

    LQ.Context memory ctx = LQ.newContext(pool, config);
    LQ.Action memory action = _determineAction(ctx);

    (address debtToken, address collToken) = ctx.tokens();

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: action.amountOwedToPool,
        incentiveBps: ctx.incentiveBps,
        dir: action.dir,
        isToken0Debt: ctx.isToken0Debt,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    poolConfigs[pool].lastRebalance = uint64(block.timestamp);
    IFPMM(pool).rebalance(action.amount0Out, action.amount1Out, hookData);
    if (!_getHookCalled(pool)) {
      revert LS_HOOK_NOT_CALLED();
    }

    // slither-disable-start incorrect-equality
    emit LiquidityMoved({
      pool: pool,
      direction: action.dir,
      tokenGivenToPool: action.dir == LQ.Direction.Expand ? debtToken : collToken,
      amountGivenToPool: action.amountOwedToPool,
      tokenTakenFromPool: action.dir == LQ.Direction.Expand ? collToken : debtToken,
      amountTakenFromPool: action.amount0Out + action.amount1Out // only one is positive
    });
    // slither-disable-end incorrect-equality
  }

  /**
   * @notice Hook called by FPMM during rebalance to handle token transfers
   * @dev Virtual function that can be overridden for custom callback handling
   * @param sender The address that initiated the rebalance (must be this contract)
   * @param amount0Out The amount of token0 to be sent from the pool
   * @param amount1Out The amount of token1 to be sent from the pool
   * @param data Encoded callback data containing rebalance parameters
   */
  function onRebalance(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external virtual {
    address pool = msg.sender;
    _ensurePool(pool);
    if (sender != address(this)) revert LS_INVALID_SENDER();

    LQ.CallbackData memory cb = abi.decode(data, (LQ.CallbackData));
    _handleCallback(pool, amount0Out, amount1Out, cb);
    _setHookCalled(pool);
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
   * @param idealDebtToExpand The calculated ideal amount of debt tokens to add to pool
   * @param idealCollateralToPay The calculated ideal amount of collateral to receive from pool
   * @return debtToExpand The actual debt amount to expand (may be less than ideal)
   * @return collateralToPay The actual collateral amount to receive (adjusted proportionally)
   */
  function _clampExpansion(
    LQ.Context memory, // used in concrete implementations
    uint256 idealDebtToExpand,
    uint256 idealCollateralToPay
  ) internal view virtual returns (uint256 debtToExpand, uint256 collateralToPay) {
    return (idealDebtToExpand, idealCollateralToPay);
  }

  /**
   * @notice Clamps contraction amounts based on strategy-specific constraints
   * @dev Override this method to limit contraction based on available collateral
   *      Default implementation returns ideal amounts unchanged
   * @param idealDebtToContract The calculated ideal amount of debt tokens to receive from pool
   * @param idealCollateralToReceive The calculated ideal amount of collateral to add to pool
   * @return debtToContract The actual debt amount to contract (may be less than ideal)
   * @return collateralToReceive The actual collateral amount to send (adjusted proportionally)
   */
  function _clampContraction(
    LQ.Context memory, // used in concrete implementations
    uint256 idealDebtToContract,
    uint256 idealCollateralToReceive
  ) internal view virtual returns (uint256 debtToContract, uint256 collateralToReceive) {
    return (idealDebtToContract, idealCollateralToReceive);
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
   * @param incentiveBps The rebalance incentive in basis points (for event emission only)
   */
  function _addPool(address pool, address debtToken, uint64 cooldown, uint32 incentiveBps) internal virtual {
    if (pool == address(0)) revert LS_POOL_MUST_BE_SET();
    if (!pools.add(pool)) revert LS_POOL_ALREADY_EXISTS(); // Ensure pool is added
    bool isToken0Debt = debtToken == IFPMM(pool).token0();
    if (!isToken0Debt && IFPMM(pool).token1() != debtToken) {
      revert LS_DEBT_TOKEN_NOT_IN_POOL();
    }

    poolConfigs[pool] = PoolConfig({ isToken0Debt: isToken0Debt, lastRebalance: 0, rebalanceCooldown: cooldown });

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

    uint256 token1Out = LQ.scaleFromTo(numerator, denominator, 1e18, ctx.token1Dec);
    uint256 token0In = LQ.convertWithRateScalingAndFee(
      token1Out,
      ctx.token1Dec,
      ctx.token0Dec,
      ctx.prices.oracleDen,
      ctx.prices.oracleNum,
      LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
      LQ.BASIS_POINTS_DENOMINATOR
    );

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
    uint256 denominator = (ctx.prices.oracleNum * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token0Out = LQ.scaleFromTo(numerator, denominator, 1e18, ctx.token0Dec);

    uint256 token1In = LQ.convertWithRateScalingAndFee(
      token0Out,
      ctx.token0Dec,
      ctx.token1Dec,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
      LQ.BASIS_POINTS_DENOMINATOR
    );

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
   * @param idealDebtToExpand The amount of debt tokens to add to the pool
   * @param idealCollateralToPay The amount of collateral tokens to receive from the pool
   * @return action The constructed expansion action
   */
  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 idealDebtToExpand,
    uint256 idealCollateralToPay
  ) internal view returns (LQ.Action memory action) {
    (uint256 debtToExpand, uint256 collateralToPay) = _clampExpansion(ctx, idealDebtToExpand, idealCollateralToPay);

    return ctx.newExpansion(debtToExpand, collateralToPay);
  }

  /**
   * @notice Builds a contraction action when pool price is below oracle price
   * @dev Must be implemented by concrete strategies to define how to handle liquidity constraints
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtToContract The amount of debt tokens to receive from the pool
   * @param idealCollateralToReceive The amount of collateral tokens to add to the pool
   * @return action The constructed contraction action
   */
  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 idealDebtToContract,
    uint256 idealCollateralToReceive
  ) internal view returns (LQ.Action memory action) {
    (uint256 debtToContract, uint256 collateralToReceive) = _clampContraction(
      ctx,
      idealDebtToContract,
      idealCollateralToReceive
    );

    return ctx.newContraction(debtToContract, collateralToReceive);
  }

  /**
   * @notice Sets a transient storage flag indicating the hook was called for a pool
   * @dev Uses EIP-1153 transient storage (tstore) to track hook calls within a single transaction
   *      This ensures the flag is automatically cleared after the transaction completes
   * @param pool The address of the pool being rebalanced
   */
  function _setHookCalled(address pool) internal {
    bytes32 key = bytes32(uint256(uint160(pool)));
    // solhint-disable-next-line no-inline-assembly
    assembly {
      tstore(key, true)
    }
  }

  /**
   * @notice Checks if the hook was called for a pool in the current transaction
   * @dev Uses EIP-1153 transient storage (tload) to read the hook call flag
   *      Returns false if the flag was never set or if called in a different transaction
   * @param pool The address of the pool being checked
   * @return hookCalled True if the hook was called for this pool in the current transaction
   */
  function _getHookCalled(address pool) private view returns (bool hookCalled) {
    bytes32 key = bytes32(uint256(uint160(pool)));
    // solhint-disable-next-line no-inline-assembly
    assembly {
      hookCalled := tload(key)
    }
  }
}
