// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20MintableBurnable } from "../common/IERC20MintableBurnable.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { IReserveV2 } from "../interfaces/IReserveV2.sol";
import { IReserveLiquidityStrategy } from "../interfaces/IReserveLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "../libraries/LiquidityStrategyTypes.sol";

contract ReserveLiquidityStrategy is IReserveLiquidityStrategy, LiquidityStrategy {
  using LQ for LQ.Context;
  using SafeERC20 for IERC20;

  /* ============================================================ */
  /* ==================== State Variables ======================= */
  /* ============================================================ */

  /// @notice The reserve contract that holds collateral
  IReserveV2 public reserve;

  /* ============================================================ */
  /* ======================= Constructor ======================== */
  /* ============================================================ */

  /**
   * @notice Disables initializers on implementation contracts.
   * @param disable Set to true to disable initializers (for proxy pattern).
   */
  constructor(bool disable) LiquidityStrategy(disable) {}

  /**
   * @notice Initializes the ReserveLiquidityStrategy contract
   * @param _initialOwner The initial owner of the contract
   * @param _reserve The Mento Protocol Reserve contract address
   */
  function initialize(address _initialOwner, address _reserve) public initializer {
    __LiquidityStrategy_init(_initialOwner);
    if (_reserve == address(0)) revert RLS_INVALID_RESERVE();
    reserve = IReserveV2(_reserve);
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
    reserve = IReserveV2(_reserve);

    emit ReserveSet(oldReserve, _reserve);
  }

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Clamps contraction amounts based on Reserve's collateral balance
   * @dev Reserve has unlimited minting capacity for expansions so no clamping needed
   *      For contractions, checks Reserve collateral balance and adjusts if insufficient
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
    uint256 collateralBalance = IERC20(collateralToken).balanceOf(address(reserve));

    // slither-disable-next-line incorrect-equality
    if (collateralBalance == 0) revert RLS_RESERVE_OUT_OF_COLLATERAL();

    if (collateralBalance < idealCollateralToReceive) {
      collateralToReceive = collateralBalance;
      debtToContract = ctx.convertToDebtWithFee(collateralBalance, BPS_DENOMINATOR, BPS_DENOMINATOR - ctx.incentiveBps);
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
    if (cb.dir == LQ.Direction.Expand) {
      // Expansion: Pool price > oracle price
      // Reserve provides debt to pool, receives collateral from pool
      uint256 collTokenFromPool = cb.isToken0Debt ? amount1Out : amount0Out;
      _transferToReserve(cb.collToken, collTokenFromPool);
      _transferToPool(cb.debtToken, pool, cb.amountOwedToPool);
    } else {
      // Contraction: Pool price < oracle price
      // Reserve provides collateral to pool, receives debt from pool
      uint256 debtTokenFromPool = cb.isToken0Debt ? amount0Out : amount1Out;
      _transferToReserve(cb.debtToken, debtTokenFromPool);
      _transferToPool(cb.collToken, pool, cb.amountOwedToPool);
    }
  }

  /**
   * @notice Transfer tokens into the pool and pay incentive
   * @param token The token to transfer in
   * @param pool The pool to transfer to
   * @param amount Amount to send to the pool
   */
  function _transferToPool(address token, address pool, uint256 amount) internal {
    if (reserve.isStableAsset(token)) {
      // Mint stable assets directly
      IERC20MintableBurnable(token).mint(pool, amount);
    } else if (reserve.isCollateralAsset(token)) {
      // Transfer collateral from reserve
      if (!reserve.transferCollateralAsset(token, pool, amount)) revert RLS_COLLATERAL_TO_POOL_FAILED();
    } else {
      revert RLS_TOKEN_IN_NOT_SUPPORTED();
    }
  }

  /**
   * @notice Transfer tokens out from the pool back to reserve
   * @param token The token to transfer out
   * @param amount The amount to transfer
   */
  function _transferToReserve(address token, uint256 amount) internal {
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
