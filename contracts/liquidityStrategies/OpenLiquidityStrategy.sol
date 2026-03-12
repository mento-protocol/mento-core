// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC20Upgradeable as IERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
// solhint-disable-next-line max-line-length
import { SafeERC20Upgradeable as SafeERC20 } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { IOpenLiquidityStrategy } from "../interfaces/IOpenLiquidityStrategy.sol";
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

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Stores the caller as the rebalancer before rebalance logic executes
   */
  function _beforeRebalance(address /* pool */) internal override {
    _setRebalancer(_msgSender());
  }

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
    // If the caller is the zero address, return the ideal amounts used for external view call to determineAction
    if (msg.sender == address(0)) return (idealDebtToExpand, idealCollateralToPay);
    address debtToken = ctx.debtToken();
    uint256 debtBalance = IERC20(debtToken).balanceOf(msg.sender);

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
    // If the caller is the zero address, return the ideal amounts used for external view call to determineAction
    if (msg.sender == address(0)) return (idealDebtToContract, idealCollateralToReceive);
    address collateralToken = ctx.collateralToken();
    uint256 collateralBalance = IERC20(collateralToken).balanceOf(msg.sender);

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
    // slither-disable-next-line arbitrary-send-erc20
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
}
