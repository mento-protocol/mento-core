// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { ILiquidityPolicy } from "./Interfaces/ILiquidityPolicy.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "./Interfaces/ICollateralRegistry.sol";

contract CDPPolicy is ILiquidityPolicy, Ownable {
  mapping(address => address) public deptTokenStabilityPool;
  mapping(address => address) public deptTokenCollateralRegistry;
  // Fees are in 18 decimals in LiquityV2 1e18 = 100%
  mapping(address => uint256) public deptTokenMaxRedemptionFee;

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external onlyOwner {
    deptTokenStabilityPool[debtToken] = stabilityPool;
  }

  function name() external pure returns (string memory) {
    return "CDPPolicy";
  }

  /* ============================================================ */
  /* ===================== External Functions =================== */
  /* ============================================================ */

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

  function _handlePoolPriceAbove(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleDen * ctx.reserves.reserveNum - ctx.prices.oracleNum * ctx.reserves.reserveDen;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1OutRaw = numerator / denominator;
    uint256 token1Out = LQ.scaleFromTo(token1OutRaw, 1e18, ctx.token1Dec);
    uint256 token0InRaw = (token1Out * ctx.prices.oracleDen) / ctx.prices.oracleNum;

    uint256 token0In = LQ.scaleFromTo(token0InRaw, ctx.token1Dec, ctx.token0Dec);

    if (ctx.isToken0Debt) {
      // ON/OD < RN/RD
      // ON/OD < CollR/DebtR
      action = _handleExpansion(ctx, token0In, token1Out);
    } else {
      // ON/OD < RN/RD
      // ON/OD < DebtR/CollR
      action = _handleContraction(ctx, token0In, token1Out);
    }
    // TODO: add what need to go here
    return (false, action);
  }

  function _handlePoolPriceBelow(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleNum * ctx.reserves.reserveDen - ctx.prices.oracleDen * ctx.reserves.reserveNum;
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1InRaw = numerator / denominator;
    uint256 token1In = LQ.scaleFromTo(token1InRaw, 18, ctx.token1Dec);

    uint256 token0OutRaw = (token1In * ctx.prices.oracleDen) / ctx.prices.oracleNum;
    uint256 token0Out = LQ.scaleFromTo(token0OutRaw, ctx.token1Dec, ctx.token0Dec);

    if (ctx.isToken0Debt) {
      // ON/OD > RN/RD
      // ON/OD > CollR/DebtR
      action = _handleContraction(ctx, token1In, token0Out);
    } else {
      // ON/OD > RN/RD
      // ON/OD > DebtR/CollR
      action = _handleExpansion(ctx, token1In, token0Out);
    }

    return (true, action);
  }

  /// add debt token from stabilityPool balance to FPMM
  /// take collateral from FPMM and send to stabilityPool including incentive
  /// add debt token from stabilityPool balance to FPMM
  /// take collateral from FPMM and send to stabilityPool including incentive
  function _handleExpansion(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address stabilityPool = deptTokenStabilityPool[debtToken];
    // TODO: check if call StabilityPool.getTotalBoldDeposits() is needed
    uint256 stabilityPoolBalance = IERC20(debtToken).balanceOf(address(stabilityPool));

    if (stabilityPoolBalance <= 1e18) revert("CDPPolicy: STABILITY_POOL_BALANCE_TOO_LOW");
    stabilityPoolBalance -= 1e18;

    if (amountIn > stabilityPoolBalance) {
      amountIn = stabilityPoolBalance;

      if (ctx.isToken0Debt) {
        uint256 amountOutRaw = (amountIn * ctx.prices.oracleNum) / ctx.prices.oracleDen;
        amountOut = LQ.scaleFromTo(amountOutRaw, ctx.token0Dec, ctx.token1Dec);
      } else {
        uint256 amountOutRaw = (amountIn * ctx.prices.oracleDen) / ctx.prices.oracleNum;
        amountOut = LQ.scaleFromTo(amountOutRaw, ctx.token1Dec, ctx.token0Dec);
      }
      // TODO: verify here the ordering scaling conversion & adding the incentive
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
    action.data = abi.encode(stabilityPool);
    return action;
  }

  /// take dept token from fpmm for colateral token from stabilityPool/redemptions
  function _handleContraction(
    LQ.Context memory ctx,
    uint256 amountIn, // collateral token
    uint256 amountOut // debt token
  ) internal view returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address collateralToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
    address stabilityPool = deptTokenStabilityPool[debtToken];
    address collateralRegistry = deptTokenCollateralRegistry[debtToken];
    // TODO: check if call StabilityPool.getCollateralBalance() is needed
    uint256 stabilityPoolCollateralBalance = IERC20(collateralToken).balanceOf(address(stabilityPool));

    if (amountIn > stabilityPoolCollateralBalance) {
      uint256 amountFromStabilityPool = stabilityPoolCollateralBalance;

      uint256 amountForStabilityPool;
      if (ctx.isToken0Debt) {
        // token1 to token0
        amountForStabilityPool = (amountFromStabilityPool * ctx.prices.oracleDen) / ctx.prices.oracleNum;
        amountForStabilityPool = LQ.scaleFromTo(amountForStabilityPool, ctx.token1Dec, ctx.token0Dec);
      } else {
        // token0 to token1
        amountForStabilityPool = (amountFromStabilityPool * ctx.prices.oracleNum) / ctx.prices.oracleDen;
        amountForStabilityPool = LQ.scaleFromTo(amountForStabilityPool, ctx.token0Dec, ctx.token1Dec);
      }

      // TODO: Double check the order of operations here, and when does the incentive needs to be applied
      amountForStabilityPool =
        (amountForStabilityPool * (LQ.BASIS_POINTS_DENOMINATOR + ctx.incentiveBps)) /
        LQ.BASIS_POINTS_DENOMINATOR;

      uint256 amountForRedemption = amountOut - amountForStabilityPool;

      uint256 redeemableAmount = calculateAmountAvailableFromRedemption(
        amountForRedemption,
        debtToken,
        collateralRegistry
      );

      amountOut = amountForStabilityPool + redeemableAmount;
    }

    action.pool = ctx.pool;
    action.dir = LQ.Direction.Expand;
    action.liquiditySource = LQ.LiquiditySource.CDP;

    if (ctx.isToken0Debt) {
      action.amount0Out = amountOut;
      action.amount1Out = 0;
    } else {
      action.amount0Out = 0;
      action.amount1Out = amountOut;
    }
    action.inputAmount = amountIn;
    action.incentiveBps = ctx.incentiveBps;
    action.data = abi.encode(""); // TODO: add data so the Strategy knows how much is payed to the stability Pool etc.might be derivable from the amount taken from the fpmm
  }

  function calculateAmountAvailableFromRedemption(
    uint256 amountForRedemption,
    address debtToken,
    address collateralRegistry
  ) internal view returns (uint256) {
    // TODO: for this calculation we need a parameter uint256 constant REDEMPTION_BETA = 1; from the Constants.sol file
    // Since this value is currently set to 1 we can ignore it but we should add a way of querying it.
    // formula for max amount that can be redeemed given the max fee we are willing to pay:
    // amountToRedeem = totalSupply * REDEMPTION_BETA * (maxFee - decayedBaseFee)
    uint256 decayedBaseFee = ICollateralRegistry(collateralRegistry).getRedemptionRateWithDecay();
    uint256 totalDebtTokenSupply = IERC20(debtToken).totalSupply();
    uint256 maxRedemptionFee = deptTokenMaxRedemptionFee[debtToken];
    uint256 maxAmountToRedeem = (totalDebtTokenSupply * (maxRedemptionFee - decayedBaseFee)) / 1e18;

    if (amountForRedemption > maxAmountToRedeem) {
      amountForRedemption = maxAmountToRedeem;
    }

    return amountForRedemption;
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
