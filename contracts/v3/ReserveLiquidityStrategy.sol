// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MintableBurnable } from "../common/IERC20MintableBurnable.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { IReserve } from "../interfaces/IReserve.sol";
import { IReserveLiquidityStrategy } from "./interfaces/IReserveLiquidityStrategy.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";

contract ReserveLiquidityStrategy is IReserveLiquidityStrategy, LiquidityStrategy {
  using LQ for LQ.Context;
  using SafeERC20 for IERC20;

  /* ============================================================ */
  /* ==================== State Variables ======================= */
  /* ============================================================ */

  /// @notice The reserve contract that holds collateral
  IReserve public reserve;

  /* ============================================================ */
  /* ======================= Constructor ======================== */
  /* ============================================================ */

  /**
   * @notice Constructor
   * @param _initialOwner The initial owner of the contract
   * @param _reserve The Mento Protocol Reserve contract address
   */
  constructor(address _initialOwner, address _reserve) LiquidityStrategy(_initialOwner) {
    reserve = IReserve(_reserve);
    emit ReserveSet(address(0), _reserve);
  }

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc IReserveLiquidityStrategy
  function addPool(address pool, address debtToken, uint64 cooldown, uint32 incentiveBps) external onlyOwner {
    LiquidityStrategy._addPool(pool, debtToken, cooldown, incentiveBps);
  }

  /// @inheritdoc IReserveLiquidityStrategy
  function removePool(address pool) external onlyOwner {
    LiquidityStrategy._removePool(pool);
  }

  /// @inheritdoc IReserveLiquidityStrategy
  function setReserve(address _reserve) external onlyOwner {
    if (_reserve == address(0)) revert RLS_INVALID_RESERVE();

    address oldReserve = address(reserve);
    reserve = IReserve(_reserve);

    emit ReserveSet(oldReserve, _reserve);
  }

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Builds an expansion action using the Reserve's unlimited minting capacity
   * @dev Reserve strategy doesn't need to check liquidity for expansions (can mint)
   * @param ctx The liquidity context
   * @param expansionAmount The amount of debt tokens to mint and add to pool
   * @param collateralPayed The amount of collateral to receive from pool
   * @return action The expansion action
   */
  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 expansionAmount,
    uint256 collateralPayed
  ) internal pure override returns (LQ.Action memory action) {
    return ctx.newExpansion(expansionAmount, collateralPayed);
  }

  /**
   * @notice Builds a contraction action limited by Reserve's collateral balance
   * @dev Checks Reserve collateral balance and adjusts amounts if insufficient
   * @param ctx The liquidity context
   * @param contractionAmount The amount of debt tokens to burn (receive from pool)
   * @param collateralReceived The amount of collateral to send to pool
   * @return action The contraction action
   */
  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 contractionAmount,
    uint256 collateralReceived
  ) internal view override returns (LQ.Action memory action) {
    address collateralToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
    uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(reserve));

    if (collateralBalance == 0) revert RLS_RESERVE_OUT_OF_COLLATERAL();

    if (collateralBalance < collateralReceived) {
      collateralReceived = collateralBalance;
      contractionAmount = ctx.convertToDebtToken(collateralBalance);
    }

    return ctx.newContraction(contractionAmount, collateralReceived);
  }

  /* ============================================================ */
  /* ================= Callback Implementation ================== */
  /* ============================================================ */

  /**
   * @notice Handles the rebalance callback by managing token flows with the Reserve
   * @dev Determines token flow direction and calls appropriate transfer functions
   * @param pool The address of the FPMM pool
   * @param amount0Out The amount of token0 being sent from the pool
   * @param amount1Out The amount of token1 being sent from the pool
   * @param cb The callback data containing rebalance parameters
   */
  function _handleCallback(
    address pool,
    uint256 amount0Out,
    uint256 amount1Out,
    LQ.CallbackData memory cb
  ) internal override {
    address tokenIn;
    address tokenOut;
    uint256 amountOut;

    if (cb.dir == LQ.Direction.Expand) {
      // Expansion: Pool price > oracle price
      // Reserve provides debt to pool, receives collateral from pool
      tokenIn = cb.debtToken;
      tokenOut = cb.collateralToken;
      amountOut = cb.isToken0Debt ? amount1Out : amount0Out;
    } else {
      // Contraction: Pool price < oracle price
      // Reserve provides collateral to pool, receives debt from pool
      tokenIn = cb.collateralToken;
      tokenOut = cb.debtToken;
      amountOut = cb.isToken0Debt ? amount0Out : amount1Out;
    }

    // Handle token going INTO the pool
    uint256 incentiveAmount = LQ.incentiveAmount(cb.inputAmount, cb.incentiveBps);
    uint256 amountToPool = cb.inputAmount - incentiveAmount;
    _transferTokenIn(tokenIn, pool, amountToPool, incentiveAmount);

    // Handle token coming OUT of the pool
    _transferTokenOut(tokenOut, amountOut);
  }

  /**
   * @notice Transfer tokens into the pool and pay incentive
   * @param token The token to transfer in
   * @param pool The pool to transfer to
   * @param amountToPool Amount to send to the pool
   * @param incentiveAmount Incentive amount to send to this contract
   */
  function _transferTokenIn(address token, address pool, uint256 amountToPool, uint256 incentiveAmount) internal {
    if (reserve.isStableAsset(token)) {
      // Mint stable assets directly
      IERC20MintableBurnable(token).mint(pool, amountToPool);
      if (incentiveAmount > 0) {
        IERC20MintableBurnable(token).mint(address(this), incentiveAmount);
      }
    } else if (reserve.isCollateralAsset(token)) {
      // Transfer collateral from reserve
      if (!reserve.transferExchangeCollateralAsset(token, payable(pool), amountToPool))
        revert RLS_COLLATERAL_TO_POOL_FAILED();
      if (incentiveAmount > 0) {
        if (!reserve.transferExchangeCollateralAsset(token, payable(address(this)), incentiveAmount))
          revert RLS_INCENTIVE_TRANSFER_FAILED();
      }
    } else {
      revert RLS_TOKEN_IN_NOT_SUPPORTED();
    }
  }

  /**
   * @notice Transfer tokens out from the pool back to reserve
   * @param token The token to transfer out
   * @param amount The amount to transfer
   */
  function _transferTokenOut(address token, uint256 amount) internal {
    if (amount == 0) return;

    if (reserve.isStableAsset(token)) {
      // Burn stable assets received from pool
      IERC20MintableBurnable(token).burn(amount);
    } else if (reserve.isCollateralAsset(token)) {
      // Transfer collateral back to reserve
      IERC20(token).safeTransfer(address(reserve), amount);
    } else {
      revert RLS_TOKEN_OUT_NOT_SUPPORTED();
    }
  }
}
