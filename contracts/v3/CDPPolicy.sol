// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { ICDPPolicy } from "./Interfaces/ICDPPolicy.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";

import { console } from "forge-std/console.sol";

contract CDPPolicy is ICDPPolicy, Ownable {
  mapping(address => address) public deptTokenStabilityPool;

  mapping(address => address) public deptTokenCollateralRegistry;

  // For now stored in a mapping as it is not readable in the collateral registry
  mapping(address => uint256) public deptTokenRedemptionBeta;

  uint256 constant bpsToFeeScaler = 1e14;

  constructor(
    address[] memory debtTokens,
    address[] memory stabilityPools,
    address[] memory collateralRegistries,
    uint256[] memory redemptionBetas
  ) Ownable() {
    if (
      debtTokens.length != stabilityPools.length ||
      debtTokens.length != collateralRegistries.length ||
      debtTokens.length != redemptionBetas.length
    ) revert CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();

    for (uint256 i = 0; i < debtTokens.length; i++) {
      _setDeptTokenStabilityPool(debtTokens[i], stabilityPools[i]);
      _setDeptTokenCollateralRegistry(debtTokens[i], collateralRegistries[i]);
      _setDeptTokenRedemptionBeta(debtTokens[i], redemptionBetas[i]);
    }
  }

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  function name() external pure returns (string memory) {
    return "CDPPolicy";
  }

  /* ============================================================ */
  /* ===================== External Functions =================== */
  /* ============================================================ */

  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external onlyOwner {
    _setDeptTokenStabilityPool(debtToken, stabilityPool);
  }

  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external onlyOwner {
    _setDeptTokenCollateralRegistry(debtToken, collateralRegistry);
  }

  function setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) external onlyOwner {
    _setDeptTokenRedemptionBeta(debtToken, redemptionBeta);
  }

  function determineAction(LQ.Context memory ctx) external view returns (bool shouldAct, LQ.Action memory action) {
    if (ctx.prices.poolPriceAbove) {
      console.log("handlePoolPriceAbove");
      return _handlePoolPriceAbove(ctx);
    } else {
      console.log("handlePoolPriceBelow");
      return _handlePoolPriceBelow(ctx);
    }
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  function _setDeptTokenStabilityPool(address debtToken, address stabilityPool) internal {
    deptTokenStabilityPool[debtToken] = stabilityPool;
  }

  function _setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) internal {
    deptTokenCollateralRegistry[debtToken] = collateralRegistry;
  }

  function _setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) internal {
    deptTokenRedemptionBeta[debtToken] = redemptionBeta;
  }

  function _handlePoolPriceAbove(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleDen * ctx.reserves.reserveNum - ctx.prices.oracleNum * ctx.reserves.reserveDen;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1Out = LQ.convertWithRateScaling(1, 1e18, ctx.token1Dec, numerator, denominator);

    uint256 token0In = LQ.convertWithRateScalingAndFee(
      token1Out,
      ctx.token1Dec,
      ctx.token0Dec,
      ctx.prices.oracleDen,
      ctx.prices.oracleNum,
      LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
      LQ.BASIS_POINTS_DENOMINATOR
    );
    console.log("token0In", token0In);
    console.log("token1Out", token1Out);

    if (ctx.isToken0Debt) {
      // ON/OD < RN/RD
      // ON/OD < CollR/DebtR
      action = _handleExpansion(ctx, token0In, token1Out);
      shouldAct = true;
    } else {
      console.log("handleContraction");
      // ON/OD < RN/RD
      // ON/OD < DebtR/CollR
      action = _handleContraction(ctx, token0In, token1Out);
      shouldAct = true;
    }
    return (shouldAct, action);
  }

  function _handlePoolPriceBelow(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleNum * ctx.reserves.reserveDen - ctx.prices.oracleDen * ctx.reserves.reserveNum;
    uint256 denominator = (ctx.prices.oracleNum * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token0Out = LQ.convertWithRateScaling(1, 1e18, ctx.token0Dec, numerator, denominator);

    uint256 token1In = LQ.convertWithRateScalingAndFee(
      token0Out,
      ctx.token0Dec,
      ctx.token1Dec,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
      LQ.BASIS_POINTS_DENOMINATOR
    );
    console.log("token1In", token1In);
    console.log("token0Out", token0Out);

    if (ctx.isToken0Debt) {
      // ON/OD > RN/RD
      // ON/OD > CollR/DebtR
      action = _handleContraction(ctx, token1In, token0Out);
      shouldAct = true;
    } else {
      // ON/OD > RN/RD
      // ON/OD > DebtR/CollR
      action = _handleExpansion(ctx, token1In, token0Out);
      shouldAct = true;
    }

    return (shouldAct, action);
  }

  /// add debt token from stabilityPool balance to FPMM
  /// take collateral from FPMM and send to stabilityPool including incentive
  function _handleExpansion(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address collToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
    address stabilityPool = deptTokenStabilityPool[debtToken];
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
    action.liquiditySource = LQ.LiquiditySource.CDP;

    if (ctx.isToken0Debt) {
      action.amount0Out = 0;
      action.amount1Out = amountOut;
    } else {
      action.amount0Out = amountOut;
      action.amount1Out = 0;
    }
    action.inputAmount = amountIn;
    action.incentiveBps = ctx.incentiveBps;
    action.data = abi.encode(debtToken, collToken, stabilityPool);
    return action;
  }

  /// take dept token from fpmm for colateral token from stabilityPool/redemptions
  function _handleContraction(
    LQ.Context memory ctx,
    uint256 amountIn, // collateral tokken
    uint256 amountOut // debt token
  ) internal view returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address collToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
    address collateralRegistry = deptTokenCollateralRegistry[debtToken];
    (uint256 amountToRedeem, uint256 amountReceived) = calculateAmountToRedeem(
      amountOut,
      debtToken,
      collateralRegistry,
      ctx
    );

    action.pool = ctx.pool;
    action.dir = LQ.Direction.Contract;
    action.liquiditySource = LQ.LiquiditySource.CDP;

    if (ctx.isToken0Debt) {
      action.amount0Out = amountToRedeem;
      action.amount1Out = 0;
    } else {
      action.amount0Out = 0;
      action.amount1Out = amountToRedeem;
    }
    action.inputAmount = amountReceived;
    action.incentiveBps = ctx.incentiveBps;
    action.data = abi.encode(debtToken, collToken, collateralRegistry);
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
    console.log("totalDebtTokenSupply", totalDebtTokenSupply);

    uint256 maxRedemptionFee = ctx.incentiveBps * bpsToFeeScaler;
    uint256 redemptionBeta = deptTokenRedemptionBeta[debtToken];

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
  ) internal view returns (uint256 amountReceived) {
    (uint256 debtTokenDec, uint256 collTokenDec) = ctx.isToken0Debt
      ? (ctx.token0Dec, ctx.token1Dec)
      : (ctx.token1Dec, ctx.token0Dec);

    // need to scale the redeemed debt fraction to 1e18 since fees are in 1e18
    uint256 redeemedDebtFraction = (amountToRedeem * 1e18) / totalDebtTokenSupply;
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

  function _emptyAction(address pool) internal pure returns (LQ.Action memory) {
    return
      LQ.Action({
        pool: pool,
        dir: LQ.Direction.Expand,
        liquiditySource: LQ.LiquiditySource.Reserve,
        amount0Out: 0,
        amount1Out: 0,
        inputAmount: 0,
        incentiveBps: 0,
        data: ""
      });
  }
}
