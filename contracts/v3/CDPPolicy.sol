// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { ICDPPolicy } from "./Interfaces/ICDPPolicy.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "./Interfaces/ICollateralRegistry.sol";

import { console } from "forge-std/console.sol";

contract CDPPolicy is ICDPPolicy, Ownable {
  mapping(address => address) public deptTokenStabilityPool;
<<<<<<< HEAD
  mapping(address => address) public deptTokenCollateralRegistry;
  // Fees are in 18 decimals in LiquityV2 1e18 = 100%
  mapping(address => uint256) public deptTokenMaxRedemptionFee;
=======

  mapping(address => address) public deptTokenCollateralRegistry;

  // For now stored in a mapping as it is not readable in the collateral registry
  mapping(address => uint256) public deptTokenRedemptionBeta;

  uint256 constant bpsToFeeScaler = 1e14;
>>>>>>> origin/feat/cdpPolicyV2

  constructor(
    address[] memory debtTokens,
    address[] memory stabilityPools,
    address[] memory collateralRegistries,
<<<<<<< HEAD
    uint256[] memory maxRedemptionFees
=======
    uint256[] memory redemptionBetas
>>>>>>> origin/feat/cdpPolicyV2
  ) Ownable() {
    if (
      debtTokens.length != stabilityPools.length ||
      debtTokens.length != collateralRegistries.length ||
<<<<<<< HEAD
      debtTokens.length != maxRedemptionFees.length
=======
      debtTokens.length != redemptionBetas.length
>>>>>>> origin/feat/cdpPolicyV2
    ) revert CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();

    for (uint256 i = 0; i < debtTokens.length; i++) {
      _setDeptTokenStabilityPool(debtTokens[i], stabilityPools[i]);
<<<<<<< HEAD
      _setDeptTokenMaxRedemptionFee(debtTokens[i], maxRedemptionFees[i]);
      _setDeptTokenCollateralRegistry(debtTokens[i], collateralRegistries[i]);
=======
      _setDeptTokenCollateralRegistry(debtTokens[i], collateralRegistries[i]);
      _setDeptTokenRedemptionBeta(debtTokens[i], redemptionBetas[i]);
>>>>>>> origin/feat/cdpPolicyV2
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

<<<<<<< HEAD
  function setDeptTokenMaxRedemptionFee(address debtToken, uint256 maxRedemptionFee) external onlyOwner {
    _setDeptTokenMaxRedemptionFee(debtToken, maxRedemptionFee);
  }

=======
>>>>>>> origin/feat/cdpPolicyV2
  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external onlyOwner {
    _setDeptTokenCollateralRegistry(debtToken, collateralRegistry);
  }

<<<<<<< HEAD
=======
  function setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) external onlyOwner {
    _setDeptTokenRedemptionBeta(debtToken, redemptionBeta);
  }

>>>>>>> origin/feat/cdpPolicyV2
  function determineAction(LQ.Context memory ctx) external view returns (bool shouldAct, LQ.Action memory action) {
    if (ctx.prices.poolPriceAbove) {
      return _handlePoolPriceAbove(ctx);
    } else {
      return _handlePoolPriceBelow(ctx);
    }
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  function _setDeptTokenStabilityPool(address debtToken, address stabilityPool) internal {
    deptTokenStabilityPool[debtToken] = stabilityPool;
  }

<<<<<<< HEAD
  function _setDeptTokenMaxRedemptionFee(address debtToken, uint256 maxRedemptionFee) internal {
    if (maxRedemptionFee > 1e18 || maxRedemptionFee == 0) revert CDPPolicy_INVALID_MAX_REDEMPTION_FEE();
    deptTokenMaxRedemptionFee[debtToken] = maxRedemptionFee;
  }

=======
>>>>>>> origin/feat/cdpPolicyV2
  function _setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) internal {
    deptTokenCollateralRegistry[debtToken] = collateralRegistry;
  }

<<<<<<< HEAD
=======
  function _setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) internal {
    deptTokenRedemptionBeta[debtToken] = redemptionBeta;
  }

>>>>>>> origin/feat/cdpPolicyV2
  function _handlePoolPriceAbove(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleDen * ctx.reserves.reserveNum - ctx.prices.oracleNum * ctx.reserves.reserveDen;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

<<<<<<< HEAD
    uint256 token1OutRaw = numerator / denominator;
    uint256 token1Out = LQ.scaleFromTo(token1OutRaw, 1e18, ctx.token1Dec);
    uint256 token0InRaw = (token1Out * ctx.prices.oracleDen) / ctx.prices.oracleNum;

    uint256 token0In = LQ.scaleFromTo(token0InRaw, ctx.token1Dec, ctx.token0Dec);
=======
    // uint256 token1Out = (numerator * ctx.token1Dec) / (denominator * 1e18);
    uint256 token1Out = LQ.convertWithRateScaling(1, 1e18, ctx.token1Dec, numerator, denominator);

    uint256 token1OutIncentive = (token1Out * ctx.incentiveBps) / 10_000;
    uint256 tokenOutAfterIncentive = token1Out - token1OutIncentive;

    uint256 token0In = LQ.convertWithRateScaling(
      tokenOutAfterIncentive,
      ctx.token1Dec,
      ctx.token0Dec,
      ctx.prices.oracleDen,
      ctx.prices.oracleNum
    );
>>>>>>> origin/feat/cdpPolicyV2

    if (ctx.isToken0Debt) {
      // ON/OD < RN/RD
      // ON/OD < CollR/DebtR
      action = _handleExpansion(ctx, token0In, token1Out);
<<<<<<< HEAD
=======
      shouldAct = true;
>>>>>>> origin/feat/cdpPolicyV2
    } else {
      // ON/OD < RN/RD
      // ON/OD < DebtR/CollR
      action = _handleContraction(ctx, token0In, token1Out);
<<<<<<< HEAD
    }
    // TODO: add what need to go here
    return (true, action);
=======
      shouldAct = true;
    }
    return (shouldAct, action);
>>>>>>> origin/feat/cdpPolicyV2
  }

  function _handlePoolPriceBelow(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleNum * ctx.reserves.reserveDen - ctx.prices.oracleDen * ctx.reserves.reserveNum;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1InRaw = numerator / denominator;
    uint256 token1In = LQ.scaleFromTo(token1InRaw, 1e18, ctx.token1Dec);

    uint256 token0OutRaw = (token1In * ctx.prices.oracleDen) / ctx.prices.oracleNum;
    uint256 token0Out = LQ.scaleFromTo(token0OutRaw, ctx.token1Dec, ctx.token0Dec);

    if (ctx.isToken0Debt) {
      // ON/OD > RN/RD
      // ON/OD > CollR/DebtR
      action = _handleContraction(ctx, token1In, token0Out);
<<<<<<< HEAD
=======
      shouldAct = true;
>>>>>>> origin/feat/cdpPolicyV2
    } else {
      // ON/OD > RN/RD
      // ON/OD > DebtR/CollR
      action = _handleExpansion(ctx, token1In, token0Out);
<<<<<<< HEAD
    }

    return (true, action);
=======
      shouldAct = true;
    }

    return (shouldAct, action);
>>>>>>> origin/feat/cdpPolicyV2
  }

  /// add debt token from stabilityPool balance to FPMM
  /// take collateral from FPMM and send to stabilityPool including incentive
<<<<<<< HEAD
  /// add debt token from stabilityPool balance to FPMM
  /// take collateral from FPMM and send to stabilityPool including incentive
=======
>>>>>>> origin/feat/cdpPolicyV2
  function _handleExpansion(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view returns (LQ.Action memory action) {
    console.log("amountIn", amountIn);
    console.log("amountOut", amountOut);
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
<<<<<<< HEAD
=======
    address collToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
>>>>>>> origin/feat/cdpPolicyV2
    address stabilityPool = deptTokenStabilityPool[debtToken];
    // TODO: check if call StabilityPool.getTotalBoldDeposits() is needed
    uint256 stabilityPoolBalance = IERC20(debtToken).balanceOf(address(stabilityPool));

    if (stabilityPoolBalance <= 1e18) revert("CDPPolicy: STABILITY_POOL_BALANCE_TOO_LOW");
    stabilityPoolBalance -= 1e18;

    if (amountIn > stabilityPoolBalance) {
      amountIn = stabilityPoolBalance;

      if (ctx.isToken0Debt) {
<<<<<<< HEAD
        uint256 amountOutRaw = (amountIn * ctx.prices.oracleNum) / ctx.prices.oracleDen;
        amountOut = LQ.scaleFromTo(amountOutRaw, ctx.token0Dec, ctx.token1Dec);
      } else {
        uint256 amountOutRaw = (amountIn * ctx.prices.oracleDen) / ctx.prices.oracleNum;
        amountOut = LQ.scaleFromTo(amountOutRaw, ctx.token1Dec, ctx.token0Dec);
      }
      // TODO: verify here the ordering scaling conversion & adding the incentive
=======
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
>>>>>>> origin/feat/cdpPolicyV2
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
<<<<<<< HEAD
    action.data = abi.encode(stabilityPool);
=======
    action.data = abi.encode(debtToken, collToken, stabilityPool);
>>>>>>> origin/feat/cdpPolicyV2
    return action;
  }

  /// take dept token from fpmm for colateral token from stabilityPool/redemptions
  function _handleContraction(
    LQ.Context memory ctx,
    uint256 amountIn, // collateral tokken
    uint256 amountOut // debt token
  ) internal view returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
<<<<<<< HEAD
    address collateralRegistry = deptTokenCollateralRegistry[debtToken];

    uint256 amountToRedeem = calculateAmountToRedeem(amountOut, debtToken, collateralRegistry);
=======
    address collToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
    address collateralRegistry = deptTokenCollateralRegistry[debtToken];
    (uint256 amountToRedeem, uint256 amountReceived) = calculateAmountToRedeem(
      amountOut,
      debtToken,
      collateralRegistry,
      ctx
    );
>>>>>>> origin/feat/cdpPolicyV2

    action.pool = ctx.pool;
    action.dir = LQ.Direction.Expand;
    action.liquiditySource = LQ.LiquiditySource.CDP;

    if (ctx.isToken0Debt) {
      action.amount0Out = amountToRedeem;
      action.amount1Out = 0;
    } else {
      action.amount0Out = 0;
      action.amount1Out = amountToRedeem;
    }
<<<<<<< HEAD
    action.inputAmount = amountIn; // this value is not accurate as of now as it is the target amount and not updated based on what the conversion rate for redemptions is
    action.incentiveBps = ctx.incentiveBps;
    action.data = abi.encode("");
=======
    action.inputAmount = amountReceived;
    action.incentiveBps = ctx.incentiveBps;
    action.data = abi.encode(debtToken, collToken, collateralRegistry);
>>>>>>> origin/feat/cdpPolicyV2
  }

  function calculateAmountToRedeem(
    uint256 targetAmountOutForRedemption,
    address debtToken,
<<<<<<< HEAD
    address collateralRegistry
  ) internal view returns (uint256 amountToRedeem) {
    // TODO: for this calculation we need a parameter uint256 constant REDEMPTION_BETA = 1; from the Constants.sol file
    // Since this value is currently set to 1 we can ignore it but we should add a way of querying it.
    // TODO: this depends on how upgradeability on the liquityV2 contract will be implemented
=======
    address collateralRegistry,
    LQ.Context memory ctx
  ) internal view returns (uint256 amountToRedeem, uint256 amountReceived) {
>>>>>>> origin/feat/cdpPolicyV2
    // formula for max amount that can be redeemed given the max fee we are willing to pay:
    // amountToRedeem = totalSupply * REDEMPTION_BETA * (maxFee - decayedBaseFee)
    uint256 decayedBaseFee = ICollateralRegistry(collateralRegistry).getRedemptionRateWithDecay();
    uint256 totalDebtTokenSupply = IERC20(debtToken).totalSupply();

<<<<<<< HEAD
    uint256 maxRedemptionFee = deptTokenMaxRedemptionFee[debtToken];
    uint256 maxAmountToRedeem = (totalDebtTokenSupply * (maxRedemptionFee - decayedBaseFee)) / 1e18;
=======
    uint256 maxRedemptionFee = ctx.incentiveBps * bpsToFeeScaler;
    uint256 redemptionBeta = deptTokenRedemptionBeta[debtToken];

    require(maxRedemptionFee > decayedBaseFee, "CDPPolicy: REDEMPTION_FEE_TOO_LARGE");
    uint256 maxAmountToRedeem = (totalDebtTokenSupply * redemptionBeta * (maxRedemptionFee - decayedBaseFee)) / 1e18;
>>>>>>> origin/feat/cdpPolicyV2

    if (targetAmountOutForRedemption > maxAmountToRedeem) {
      amountToRedeem = maxAmountToRedeem;
    } else {
      amountToRedeem = targetAmountOutForRedemption;
    }
<<<<<<< HEAD
=======

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
>>>>>>> origin/feat/cdpPolicyV2
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
