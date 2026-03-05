// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
// solhint-disable-next-line max-line-length
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { ILiquidityStrategy } from "../interfaces/ILiquidityStrategy.sol";
import { IOpenLiquidityStrategy } from "../interfaces/IOpenLiquidityStrategy.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { LiquidityStrategyTypes as LQ } from "../libraries/LiquidityStrategyTypes.sol";

/**
 * @title OpenLiquidityStrategy
 * @notice Liquidity strategy where the caller of rebalance() acts as the liquidity source.
 * @dev The rebalancer provides tokens to the pool and receives tokens from the pool
 *      via standard ERC20 transfers. The rebalancer must approve this contract for
 *      the tokens owed to the pool before calling rebalance().
 */
contract OpenLiquidityStrategy is IOpenLiquidityStrategy, LiquidityStrategy {
  using LQ for LQ.Context;
  using SafeERC20 for IERC20;

  /// @dev Transient storage slot for the rebalancer address
  bytes32 private constant REBALANCER_TSLOT = keccak256("OpenLiquidityStrategy.rebalancer");

  /* ============================================================ */
  /* ======================= Constructor ======================== */
  /* ============================================================ */

  /**
   * @notice Disables initializers on implementation contracts.
   * @param disable Set to true to disable initializers (for proxy pattern).
   */
  constructor(bool disable) LiquidityStrategy(disable) {}

  /// @inheritdoc IOpenLiquidityStrategy
  function initialize(address _initialOwner) public initializer {
    __LiquidityStrategy_init(_initialOwner);
  }

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IOpenLiquidityStrategy
  function addPool(AddPoolParams calldata params) external onlyOwner {
    LiquidityStrategy._addPool(params);
  }

  /// @inheritdoc IOpenLiquidityStrategy
  function removePool(address pool) external onlyOwner {
    LiquidityStrategy._removePool(pool);
  }

  function rebalance(address pool) external override(ILiquidityStrategy, LiquidityStrategy) nonReentrant {
    _setRebalancer(_msgSender());

    _ensurePool(pool);
    if (_isHookCalled(pool)) {
      revert LS_CAN_ONLY_REBALANCE_ONCE(pool);
    }

    PoolConfig memory config = poolConfigs[pool];
    // Skip cooldown check for first rebalance (lastRebalance == 0)
    if (config.lastRebalance > 0 && block.timestamp < config.lastRebalance + config.rebalanceCooldown) {
      revert LS_COOLDOWN_ACTIVE();
    }

    LQ.Context memory ctx = LQ.newRebalanceContext(pool, config);
    LQ.Action memory action = _determineAction(ctx);

    (address debtToken, address collToken) = ctx.tokens();

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        amountOwedToPool: action.amountOwedToPool,
        dir: action.dir,
        isToken0Debt: ctx.isToken0Debt,
        debtToken: debtToken,
        collToken: collToken
      })
    );

    poolConfigs[pool].lastRebalance = uint32(block.timestamp);
    IFPMM(pool).rebalance(action.amount0Out, action.amount1Out, hookData);
    if (!_isHookCalled(pool)) {
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

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Clamps expansion amounts based on the rebalancer's debt token balance
   * @dev For expansions, checks the rebalancer's debt token balance and adjusts if insufficient
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtToExpand The calculated ideal amount of debt tokens to add to pool
   * @param idealCollateralToPay The calculated ideal amount of collateral to receive from pool
   * @return debtToExpand The actual debt amount to expand (may be less than ideal)
   * @return collateralToPay The actual collateral amount to receive (adjusted if balance insufficient)
   */
  function _clampExpansion(
    LQ.Context memory ctx,
    uint256 idealDebtToExpand,
    uint256 idealCollateralToPay
  ) internal view override returns (uint256 debtToExpand, uint256 collateralToPay) {
    address debtToken = ctx.debtToken();
    uint256 debtBalance = IERC20(debtToken).balanceOf(_getRebalancer());

    // slither-disable-next-line incorrect-equality
    if (debtBalance == 0) revert OLS_OUT_OF_DEBT();

    if (debtBalance < idealDebtToExpand) {
      uint256 combinedFeeMultiplier = LQ.combineFees(
        ctx.incentives.protocolIncentiveExpansion,
        ctx.incentives.liquiditySourceIncentiveExpansion
      );
      debtToExpand = debtBalance;
      collateralToPay = ctx.convertToCollateralWithFee(debtBalance, LQ.FEE_DENOMINATOR, combinedFeeMultiplier);
    } else {
      debtToExpand = idealDebtToExpand;
      collateralToPay = idealCollateralToPay;
    }

    return (debtToExpand, collateralToPay);
  }

  /**
   * @notice Clamps contraction amounts based on the rebalancer's collateral balance
   * @dev For contractions, checks the rebalancer's collateral balance and adjusts if insufficient
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtToContract The calculated ideal amount of debt tokens to receive from pool
   * @param idealCollateralToReceive The calculated ideal amount of collateral to add to pool
   * @return debtToContract The actual debt amount to contract (may be less than ideal)
   * @return collateralToReceive The actual collateral amount to send (adjusted if balance insufficient)
   */
  function _clampContraction(
    LQ.Context memory ctx,
    uint256 idealDebtToContract,
    uint256 idealCollateralToReceive
  ) internal view override returns (uint256 debtToContract, uint256 collateralToReceive) {
    address collateralToken = ctx.collateralToken();
    uint256 collateralBalance = IERC20(collateralToken).balanceOf(_getRebalancer());

    // slither-disable-next-line incorrect-equality
    if (collateralBalance == 0) revert OLS_OUT_OF_COLLATERAL();

    if (collateralBalance < idealCollateralToReceive) {
      uint256 combinedFeeMultiplier = LQ.combineFees(
        ctx.incentives.protocolIncentiveContraction,
        ctx.incentives.liquiditySourceIncentiveContraction
      );
      collateralToReceive = collateralBalance;
      debtToContract = ctx.convertToDebtWithFee(collateralBalance, LQ.FEE_DENOMINATOR, combinedFeeMultiplier);
    } else {
      collateralToReceive = idealCollateralToReceive;
      debtToContract = idealDebtToContract;
    }

    return (debtToContract, collateralToReceive);
  }

  /* ============================================================ */
  /* ================= Callback Implementation ================== */
  /* ============================================================ */

  /**
   * @notice Handles the rebalance callback by transferring tokens to/from the rebalancer
   * @dev Tokens received from the pool (minus protocol incentive) go to the rebalancer.
   *      Tokens owed to the pool are pulled from the rebalancer via transferFrom.
   * @param pool The address of the FPMM pool
   * @param amount0Out The amount of token0 sent by the pool
   * @param amount1Out The amount of token1 sent by the pool
   * @param cb The callback data containing rebalance parameters
   */
  function _handleCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    LQ.CallbackData memory cb
  ) internal override {
    PoolConfig memory config = poolConfigs[pool];
    address rebalancer = _getRebalancer();

    (address tokenFromPool, address tokenToPool, uint256 protocolIncentive) = cb.dir == LQ.Direction.Expand
      ? (cb.collToken, cb.debtToken, uint256(config.protocolIncentiveExpansion))
      : (cb.debtToken, cb.collToken, uint256(config.protocolIncentiveContraction));

    uint256 amountFromPool = amount0Out > 0 ? amount0Out : amount1Out;
    uint256 protocolIncentiveAmount = (amountFromPool * protocolIncentive) / LQ.FEE_DENOMINATOR;

    // Transfer protocol incentive to protocol fee recipient
    _transferRebalanceIncentive(tokenFromPool, protocolIncentiveAmount, config.protocolFeeRecipient);
    // Transfer remaining tokens to rebalancer (includes liquidity source incentive)
    IERC20(tokenFromPool).safeTransfer(rebalancer, amountFromPool - protocolIncentiveAmount);
    // Pull tokens from rebalancer and send to pool
    IERC20(tokenToPool).safeTransferFrom(rebalancer, pool, cb.amountOwedToPool);
  }

  /* ============================================================ */
  /* ==================== Private Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Stores the rebalancer address in transient storage
   * @param rebalancer The address of the rebalancer (msg.sender of rebalance())
   */
  function _setRebalancer(address rebalancer) private {
    bytes32 slot = REBALANCER_TSLOT;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      tstore(slot, rebalancer)
    }
  }

  /**
   * @notice Reads the rebalancer address from transient storage
   * @return rebalancer The stored rebalancer address
   */
  function _getRebalancer() private view returns (address rebalancer) {
    bytes32 slot = REBALANCER_TSLOT;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      rebalancer := tload(slot)
    }
  }

  /**
   * @notice Checks if the hook was called for a pool in the current transaction
   * @dev Mirrors LiquidityStrategy._getHookCalled (which is private) using the same key derivation
   * @param pool The address of the pool being checked
   * @return called True if the hook was called for this pool
   */
  function _isHookCalled(address pool) private view returns (bool called) {
    bytes32 key = bytes32(uint256(uint160(pool)));
    // solhint-disable-next-line no-inline-assembly
    assembly {
      called := tload(key)
    }
  }
}
