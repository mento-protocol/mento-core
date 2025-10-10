// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityStrategyTypes as LQ } from "./LiquidityStrategyTypes.sol";
import { ICDPLiquidityStrategy } from "../interfaces/ICDPLiquidityStrategy.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";

library CDPLSLib {
  using LQ for LQ.Context;

  uint256 constant BPS_TO_FEE_SCALER = 1e14;
  uint256 constant BPS_DENOMINATOR = 10_000;

  error CDPLS_STABILITY_POOL_BALANCE_TOO_LOW();
  error CDPLS_REDEMPTION_FEE_TOO_LARGE();

  /// take collateral from FPMM, put it in the stability pool in exchange for debt token,
  /// return debt token to FPMM.
  function buildExpansionAction(
    LQ.Context memory ctx,
    ICDPLiquidityStrategy.CDPConfig storage poolConfig,
    uint256 targetExpansion,
    uint256 collateralCost
  ) internal view returns (LQ.Action memory action) {
    uint256 availableDebtToken = calculateAvailablePoolBalance(poolConfig, ctx.debtToken());

    if (targetExpansion > availableDebtToken) {
      targetExpansion = availableDebtToken;
      collateralCost = ctx.convertToCollateralWithFee(targetExpansion);
    }

    return ctx.newExpansion(targetExpansion, collateralCost);
  }

  /// take debt token from FPMM, redeem against CDPs, return collateral to FPMM
  function buildContractionAction(
    LQ.Context memory ctx,
    ICDPLiquidityStrategy.CDPConfig storage cdpConfig,
    uint256 targetContraction
  ) internal view returns (LQ.Action memory action) {
    (uint256 contractionAmount, uint256 collateralReceived) = calculateAmountToRedeem(
      ctx,
      cdpConfig,
      targetContractionAmount
    );

    return ctx.newContraction(contractionAmount, collateralReceived);
  }

  function calculateAvailablePoolBalance(
    ICDPLiquidityStrategy.CDPConfig storage cdpConfig,
    address debtToken
  ) internal view returns (uint256 availableAmount) {
    uint256 stabilityPoolBalance = IERC20(debtToken).balanceOf(cdpConfig.stabilityPool);
    uint256 stabilityPoolMinBalance = IStabilityPool(cdpConfig.stabilityPool).MIN_BOLD_AFTER_REBALANCE();

    if (stabilityPoolBalance <= stabilityPoolMinBalance) revert CDPLS_STABILITY_POOL_BALANCE_TOO_LOW();

    uint256 stabilityPoolAvailable = (stabilityPoolBalance * cdpConfig.stabilityPoolPercentage) / BPS_DENOMINATOR;

    availableAmount = stabilityPoolAvailable > stabilityPoolBalance - stabilityPoolMinBalance
      ? stabilityPoolBalance - stabilityPoolMinBalance
      : stabilityPoolAvailable;
  }

  function calculateAmountToRedeem(
    LQ.Context memory ctx,
    ICDPLiquidityStrategy.CDPConfig storage cdpConfig,
    uint256 targetContractionAmount
  ) internal view returns (uint256 contractionAmount, uint256 collateralReceived) {
    // formula for max amount that can be redeemed given the max fee we are willing to pay:
    // amountToRedeem = totalSupply * REDEMPTION_BETA * (maxFee - decayedBaseFee)
    address debtToken = ctx.debtToken();
    uint256 decayedBaseFee = ICollateralRegistry(cdpConfig.collateralRegistry).getRedemptionRateWithDecay();
    uint256 totalDebtTokenSupply = IERC20(debtToken).totalSupply();

    uint256 maxRedemptionFee = ctx.incentiveBps * BPS_TO_FEE_SCALER;

    if (maxRedemptionFee < decayedBaseFee) revert CDPLS_REDEMPTION_FEE_TOO_LARGE();
    uint256 maxAmountToRedeem = (totalDebtTokenSupply *
      cdpConfig.redemptionBeta *
      (maxRedemptionFee - decayedBaseFee)) / 1e18;

    if (targetContractionAmount > maxAmountToRedeem) {
      contractionAmount = maxAmountToRedeem;
    } else {
      contractionAmount = targetContractionAmount;
    }

    collateralReceived = calculateCollateralFromRedemption(
      contractionAmount,
      decayedBaseFee,
      cdpConfig.redemptionBeta,
      totalDebtTokenSupply,
      ctx
    );
  }

  function calculateCollateralFromRedemption(
    uint256 amountToRedeem,
    uint256 decayedBaseFee,
    uint256 redemptionBeta,
    uint256 totalDebtTokenSupply,
    LQ.Context memory ctx
  ) internal pure returns (uint256 amountReceived) {
    (uint256 debtTokenDec, uint256 collTokenDec) = ctx.isToken0Debt
      ? (ctx.token0Dec, ctx.token1Dec)
      : (ctx.token1Dec, ctx.token0Dec);

    // Redemption fee formula from CollateralRegistry.sol
    // redemptionFee := decayedBaseFee + (amountToRedeem * redemptionBeta) / totalDebtTokenSupply * 1e18
    // need to scale the redeemed debt fraction to 1e18 since fees are in 1e18
    uint256 redeemedDebtFraction = (amountToRedeem * 1e18 * redemptionBeta) / totalDebtTokenSupply;
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
