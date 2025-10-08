// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";

import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";
import { ICDPPolicy } from "./Interfaces/ICDPPolicy.sol";

import { console } from "forge-std/console.sol";

abstract contract CDPPolicy is ICDPPolicy, Ownable {
  using LQ for LQ.Context;

  uint256 constant BPS_TO_FEE_SCALER = 1e14;
  uint256 constant BPS_DENOMINATOR = 10_000;

  mapping(address => CDPPolicyPoolConfig) private poolConfigs;

  /* ============================================================ */
  /* ================ Admin Functions - Pools =================== */
  /* ============================================================ */

  function addPool(
    address pool,
    address stabilityPool,
    address collateralRegistry,
    uint256 redemptionBeta,
    uint256 stabilityPoolPercentage
  ) internal virtual {
    poolConfigs[pool] = CDPPolicyPoolConfig({
      stabilityPool: stabilityPool,
      collateralRegistry: collateralRegistry,
      redemptionBeta: redemptionBeta,
      stabilityPoolPercentage: stabilityPoolPercentage
    });
  }

  function removePool(address pool) public virtual {
    delete poolConfigs[pool];
  }

  function setCDPPolicyPoolConfig(address pool, CDPPolicyPoolConfig calldata config) external onlyOwner {
    _ensurePool(pool);
    poolConfigs[pool] = config;
  }

  function getCDPPolicyPoolConfig(address pool) external view returns (CDPPolicyPoolConfig memory) {
    return poolConfigs[pool];
  }

  /* =========================================================== */
  /* =================== Virtual Functions ===================== */
  /* =========================================================== */

  function _ensurePool(address pool) internal view virtual;

  function _getStabilityPool(address pool) internal view virtual returns (address) {
    return poolConfigs[pool].stabilityPool;
  }

  function _getCollateralRegistry(address pool) internal view virtual returns (address) {
    return poolConfigs[pool].collateralRegistry;
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  function _setStabilityPool(address pool, address _stabilityPool) internal {
    poolConfigs[pool].stabilityPool = _stabilityPool;
  }

  function _setCollateralRegistry(address pool, address _collateralRegistry) internal {
    poolConfigs[pool].collateralRegistry = _collateralRegistry;
  }

  function _setRedemptionBeta(address pool, uint256 _redemptionBeta) internal {
    poolConfigs[pool].redemptionBeta = _redemptionBeta;
  }

  function _setStabilityPoolPercentage(address pool, uint256 _stabilityPoolPercentage) internal {
    if (!(0 < _stabilityPoolPercentage && _stabilityPoolPercentage < BPS_DENOMINATOR))
      revert CDPPolicy_INVALID_STABILITY_POOL_PERCENTAGE();
    poolConfigs[pool].stabilityPoolPercentage = _stabilityPoolPercentage;
  }

  /// add debt token from stabilityPool balance to FPMM
  /// take collateral from FPMM and send to stabilityPool including incentive
  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view virtual returns (LQ.Action memory action) {
    console.log("amountIn", amountIn);
    console.log("amountOut", amountOut);
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address stabilityPool = poolConfigs[ctx.pool].stabilityPool;
    uint256 availableSPAmount = _calculateAvailablePoolBalance(stabilityPool, debtToken, ctx.pool);

    if (amountIn > availableSPAmount) {
      amountIn = availableSPAmount;

      if (ctx.isToken0Debt) {
        amountOut = LQ.convertWithRateScalingAndFee(
          amountIn,
          ctx.token0Dec,
          ctx.token1Dec,
          ctx.prices.oracleNum,
          ctx.prices.oracleDen,
          LQ.BASIS_POINTS_DENOMINATOR,
          LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps
        );
      } else {
        amountOut = LQ.convertWithRateScalingAndFee(
          amountIn,
          ctx.token1Dec,
          ctx.token0Dec,
          ctx.prices.oracleDen,
          ctx.prices.oracleNum,
          LQ.BASIS_POINTS_DENOMINATOR,
          LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps
        );
      }
    }
    // slither-disable-next-line incorrect-equality
    if (amountOut == 0) revert CDPPolicy_AmountOutIs0();
    // slither-disable-next-line incorrect-equality
    if (amountIn == 0) revert CDPPolicy_AmountInIs0();

    action.pool = ctx.pool;
    action.dir = LQ.Direction.Expand;

    if (ctx.isToken0Debt) {
      action.amount0Out = 0;
      action.amount1Out = amountOut;
    } else {
      action.amount0Out = amountOut;
      action.amount1Out = 0;
    }
    action.inputAmount = amountIn;
    return action;
  }

  /// take dept token from fpmm for colateral token from stabilityPool/redemptions
  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256, // collateral token
    uint256 amountOut // debt token
  ) internal view virtual returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address collateralRegistry = poolConfigs[ctx.pool].collateralRegistry;
    (uint256 amountToRedeem, uint256 amountReceived) = _calculateAmountToRedeem(
      amountOut,
      debtToken,
      collateralRegistry,
      ctx
    );

    if (amountToRedeem == 0) revert CDPPolicy_AmountOutIs0();
    if (amountReceived == 0) revert CDPPolicy_AmountInIs0();

    action.pool = ctx.pool;
    action.dir = LQ.Direction.Contract;

    if (ctx.isToken0Debt) {
      action.amount0Out = amountToRedeem;
      action.amount1Out = 0;
    } else {
      action.amount0Out = 0;
      action.amount1Out = amountToRedeem;
    }
    action.inputAmount = amountReceived;
  }

  /**
   * @notice Calculates the available balance in the stability pool for a given debt token.
   * The available balance is capped by a minimum balance configured in the stability pool
   * and a percentage of the total balance. If the percentage is larger than the total balance
   * minus the minimum balance, the available balance is the total balance minus the minimum balance.
   * @param stabilityPool The address of the stability pool
   * @param debtToken The address of the debt token
   * @return availableAmount The available balance in the stability pool
   */
  function _calculateAvailablePoolBalance(
    address stabilityPool,
    address debtToken,
    address pool
  ) internal view returns (uint256 availableAmount) {
    uint256 stabilityPoolBalance = IERC20(debtToken).balanceOf(stabilityPool);
    uint256 stabilityPoolMinBalance = IStabilityPool(stabilityPool).MIN_BOLD_AFTER_REBALANCE();

    if (stabilityPoolBalance <= stabilityPoolMinBalance) revert CDPPolicy_StabilityPoolBalanceTooLow();

    uint256 stabilityPoolPercentage = (stabilityPoolBalance * poolConfigs[pool].stabilityPoolPercentage) /
      BPS_DENOMINATOR;
    uint256 availableAmountAfterMinBalance = stabilityPoolBalance - stabilityPoolMinBalance;

    availableAmount = stabilityPoolPercentage > availableAmountAfterMinBalance
      ? availableAmountAfterMinBalance
      : stabilityPoolPercentage;
  }

  /**
   * @notice Calculates the maximum amount of debt tokens that can be redeemed given the max fee we are willing to pay.
   * The formula is:
   * maxAmountToRedeem = totalSupply * REDEMPTION_BETA * (maxFee - decayedBaseFee)
   * @param targetAmountOutForRedemption The target amount of debt tokens to be redeemed.
   * @param debtToken The address of the debt token
   * @param collateralRegistry The address of the collateral registry
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @return amountToRedeem The amount of debt tokens to be redeemed.
   * @return amountReceived The amount of collateral to be received.
   */
  function _calculateAmountToRedeem(
    uint256 targetAmountOutForRedemption,
    address debtToken,
    address collateralRegistry,
    LQ.Context memory ctx
  ) internal view returns (uint256 amountToRedeem, uint256 amountReceived) {
    uint256 decayedBaseFee = ICollateralRegistry(collateralRegistry).getRedemptionRateWithDecay();

    uint256 totalDebtTokenSupply = IERC20(debtToken).totalSupply();
    uint256 maxRedemptionFee = ctx.incentiveBps * BPS_TO_FEE_SCALER;
    uint256 redemptionBeta = poolConfigs[ctx.pool].redemptionBeta;

    uint256 maxAmountToRedeem = (totalDebtTokenSupply * redemptionBeta * (maxRedemptionFee - decayedBaseFee)) / 1e18;

    amountToRedeem = targetAmountOutForRedemption > maxAmountToRedeem
      ? maxAmountToRedeem
      : targetAmountOutForRedemption;

    amountReceived = _calculateAmountReceived(
      amountToRedeem,
      decayedBaseFee,
      redemptionBeta,
      totalDebtTokenSupply,
      ctx
    );
  }

  /**
   * @notice Calculates the amount of collateral to be received given the amount of debt tokens to be redeemed,
   * the decayed base fee, the redemption beta and the total supply of the debt token.
   * The formula is:
   * redemptionFee = decayedBaseFee + (amountToRedeem) / (totalDebtTokenSupply * redemptionBeta)
   * amountReceived = amountToRedeem * (1e18 - redemptionFee) * oracleNumerator / oracleDenominator
   * @param amountToRedeem The amount of debt tokens to be redeemed.
   * @param decayedBaseFee The decayed base fee.
   * @param redemptionBeta The redemption beta.
   * @param totalDebtTokenSupply The total supply of the debt token.
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @return amountReceived The amount of collateral to be received.
   */
  function _calculateAmountReceived(
    uint256 amountToRedeem,
    uint256 decayedBaseFee,
    uint256 redemptionBeta,
    uint256 totalDebtTokenSupply,
    LQ.Context memory ctx
  ) internal pure returns (uint256 amountReceived) {
    (uint256 debtTokenDec, uint256 collTokenDec) = ctx.isToken0Debt
      ? (ctx.token0Dec, ctx.token1Dec)
      : (ctx.token1Dec, ctx.token0Dec);

    // need to scale the redeemed debt fraction to 1e18 since fees are in 1e18
    uint256 redeemedDebtFraction = (amountToRedeem * 1e18) / (totalDebtTokenSupply * redemptionBeta);
    uint256 redemptionFee = decayedBaseFee + redeemedDebtFraction;

    // redemption fee is capped at 100%
    redemptionFee = redemptionFee > 1e18 ? 1e18 : redemptionFee;

    (uint256 numerator, uint256 denominator) = ctx.isToken0Debt
      ? (ctx.prices.oracleNum, ctx.prices.oracleDen)
      : (ctx.prices.oracleDen, ctx.prices.oracleNum);

    return
      LQ.convertWithRateScalingAndFee(
        amountToRedeem,
        debtTokenDec,
        collTokenDec,
        numerator,
        denominator,
        1e18 - redemptionFee,
        1e18
      );
  }
}
