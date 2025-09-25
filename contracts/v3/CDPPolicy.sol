// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";
import { ICDPPolicy } from "./Interfaces/ICDPPolicy.sol";
import { ICollateralRegistry } from "./Interfaces/ICollateralRegistry.sol";

import { console } from "forge-std/console.sol";

abstract contract CDPPolicy is ICDPPolicy, Ownable {
  using LQ for LQ.Context;

  struct CDPLSPoolConfig {
    address stabilityPool;
    address collateralRegistry;
    uint256 redemptionBeta;
  }

  uint256 constant bpsToFeeScaler = 1e14;
  mapping(address => CDPLSPoolConfig) private poolConfigs;

  /* ============================================================ */
  /* ================ Admin Functions - Pools =================== */
  /* ============================================================ */

  function addPool(
    address pool,
    address stabilityPool,
    address collateralRegistry,
    uint256 redemptionBeta
  ) internal virtual {
    poolConfigs[pool] = CDPLSPoolConfig({
      stabilityPool: stabilityPool,
      collateralRegistry: collateralRegistry,
      redemptionBeta: redemptionBeta
    });
  }

  function removePool(address pool) public virtual {
    delete poolConfigs[pool];
  }

  function setDeptTokenStabilityPool(address pool, address stabilityPool) external onlyOwner {
    _ensurePool(pool);
    _setDeptTokenStabilityPool(pool, stabilityPool);
  }

  function setDeptTokenCollateralRegistry(address pool, address collateralRegistry) external onlyOwner {
    _ensurePool(pool);
    _setDeptTokenCollateralRegistry(pool, collateralRegistry);
  }

  function setDeptTokenRedemptionBeta(address pool, uint256 redemptionBeta) external onlyOwner {
    _ensurePool(pool);
    _setDeptTokenRedemptionBeta(pool, redemptionBeta);
  }

  /* =========================================================== */
  /* =================== Virtual Functions ===================== */
  /* =========================================================== */

  function _ensurePool(address pool) internal view virtual;

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  function _setDeptTokenStabilityPool(address pool, address _stabilityPool) internal {
    poolConfigs[pool].stabilityPool = _stabilityPool;
  }

  function _setDeptTokenCollateralRegistry(address pool, address _collateralRegistry) internal {
    poolConfigs[pool].collateralRegistry = _collateralRegistry;
  }

  function _setDeptTokenRedemptionBeta(address pool, uint256 _redemptionBeta) internal {
    poolConfigs[pool].redemptionBeta = _redemptionBeta;
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
    // TODO: check if call StabilityPool.getTotalBoldDeposits() is needed
    uint256 stabilityPoolBalance = IERC20(debtToken).balanceOf(address(stabilityPool));

    if (stabilityPoolBalance <= 1e18) revert("CDPPolicy: STABILITY_POOL_BALANCE_TOO_LOW");
    stabilityPoolBalance -= 1e18;

    if (amountIn > stabilityPoolBalance) {
      amountIn = stabilityPoolBalance;

      if (ctx.isToken0Debt) {
        // uint256 amountOutRaw = (amountIn * ctx.prices.oracleNum) / ctx.prices.oracleDen;
        // amountOut = LQ.scaleFromTo(amountOutRaw, ctx.token0Dec, ctx.token1Dec);
        amountOut = LQ.convertWithRateScaling(
          amountIn,
          ctx.token0Dec,
          ctx.token1Dec,
          ctx.prices.oracleNum,
          ctx.prices.oracleDen
        );
      } else {
        // uint256 amountOutRaw = (amountIn * ctx.prices.oracleDen) / ctx.prices.oracleNum;
        // amountOut = LQ.scaleFromTo(amountOutRaw, ctx.token1Dec, ctx.token0Dec);
        amountOut = LQ.convertWithRateScaling(
          amountIn,
          ctx.token1Dec,
          ctx.token0Dec,
          ctx.prices.oracleDen,
          ctx.prices.oracleNum
        );
      }
      amountOut = (amountOut * (LQ.BASIS_POINTS_DENOMINATOR + ctx.incentiveBps)) / LQ.BASIS_POINTS_DENOMINATOR;
    }

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
    // action.data = abi.encode(debtToken, collToken, stabilityPool);
    return action;
  }

  /// take dept token from fpmm for colateral token from stabilityPool/redemptions
  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256, // collateral tokken
    uint256 amountOut // debt token
  ) internal view virtual returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address collateralRegistry = poolConfigs[ctx.pool].collateralRegistry;
    (uint256 amountToRedeem, uint256 amountReceived) = calculateAmountToRedeem(
      amountOut,
      debtToken,
      collateralRegistry,
      ctx
    );

    action.pool = ctx.pool;
    action.dir = LQ.Direction.Expand;

    if (ctx.isToken0Debt) {
      action.amount0Out = amountToRedeem;
      action.amount1Out = 0;
    } else {
      action.amount0Out = 0;
      action.amount1Out = amountToRedeem;
    }
    action.inputAmount = amountReceived;
  }

  function calculateAmountToRedeem(
    uint256 targetAmountOutForRedemption,
    address debtToken,
    address collateralRegistry,
    LQ.Context memory ctx
  ) internal view returns (uint256 amountToRedeem, uint256 amountReceived) {
    // formula for max amount that can be redeemed given the max fee we are willing to pay:
    // amountToRedeem = totalSupply * REDEMPTION_BETA * (maxFee - decayedBaseFee)
    uint256 decayedBaseFee = ICollateralRegistry(collateralRegistry).getRedemptionRateWithDecay();
    uint256 totalDebtTokenSupply = IERC20(debtToken).totalSupply();

    uint256 maxRedemptionFee = ctx.incentiveBps * bpsToFeeScaler;
    uint256 redemptionBeta = poolConfigs[ctx.pool].redemptionBeta;

    require(maxRedemptionFee > decayedBaseFee, "CDPPolicy: REDEMPTION_FEE_TOO_LARGE");
    uint256 maxAmountToRedeem = (totalDebtTokenSupply * redemptionBeta * (maxRedemptionFee - decayedBaseFee)) / 1e18;

    if (targetAmountOutForRedemption > maxAmountToRedeem) {
      amountToRedeem = maxAmountToRedeem;
    } else {
      amountToRedeem = targetAmountOutForRedemption;
    }

    amountReceived = _calculateAmountReceived(
      amountToRedeem,
      decayedBaseFee,
      redemptionBeta,
      totalDebtTokenSupply,
      ctx
    );
  }

  function _calculateAmountReceived(
    uint256 amountToRedeem,
    uint256 decayedBaseFee,
    uint256 redemptionBeta,
    uint256 totalDebtTokenSupply,
    LQ.Context memory ctx
  ) internal pure returns (uint256 amountReceived) {
    uint256 redeemedDebtFraction = (amountToRedeem * 1e18) / totalDebtTokenSupply;
    uint256 redemptionFee = decayedBaseFee + redeemedDebtFraction / redemptionBeta;

    // redemption fee is capped at 100%
    redemptionFee = redemptionFee > 1e18 ? 1e18 : redemptionFee;

    (uint256 numerator, uint256 denominator) = ctx.isToken0Debt
      ? (ctx.prices.oracleNum, ctx.prices.oracleDen)
      : (ctx.prices.oracleDen, ctx.prices.oracleNum);
    amountReceived = (amountToRedeem * (1e18 - redemptionFee) * numerator) / (denominator * 1e18);

    return
      LQ.scaleFromTo(
        amountReceived,
        ctx.isToken0Debt ? ctx.token0Dec : ctx.token1Dec,
        ctx.isToken0Debt ? ctx.token1Dec : ctx.token0Dec
      );
  }
}
