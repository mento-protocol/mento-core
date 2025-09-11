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
  mapping(address => address) public deptTokenCollateralRegistry;
  // Fees are in 18 decimals in LiquityV2 1e18 = 100%
  mapping(address => uint256) public deptTokenMaxRedemptionFee;

  constructor(
    address[] memory debtTokens,
    address[] memory stabilityPools,
    address[] memory collateralRegistries,
    uint256[] memory maxRedemptionFees
  ) Ownable() {
    if (
      debtTokens.length != stabilityPools.length ||
      debtTokens.length != collateralRegistries.length ||
      debtTokens.length != maxRedemptionFees.length
    ) revert CDPPolicy_CONSTRUCTOR_ARRAY_LENGTH_MISMATCH();

    for (uint256 i = 0; i < debtTokens.length; i++) {
      _setDeptTokenStabilityPool(debtTokens[i], stabilityPools[i]);
      _setDeptTokenMaxRedemptionFee(debtTokens[i], maxRedemptionFees[i]);
      _setDeptTokenCollateralRegistry(debtTokens[i], collateralRegistries[i]);
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

  function setDeptTokenMaxRedemptionFee(address debtToken, uint256 maxRedemptionFee) external onlyOwner {
    _setDeptTokenMaxRedemptionFee(debtToken, maxRedemptionFee);
  }

  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external onlyOwner {
    _setDeptTokenCollateralRegistry(debtToken, collateralRegistry);
  }

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

  function _setDeptTokenMaxRedemptionFee(address debtToken, uint256 maxRedemptionFee) internal {
    if (maxRedemptionFee > 1e18 || maxRedemptionFee == 0) revert CDPPolicy_INVALID_MAX_REDEMPTION_FEE();
    deptTokenMaxRedemptionFee[debtToken] = maxRedemptionFee;
  }

  function _setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) internal {
    deptTokenCollateralRegistry[debtToken] = collateralRegistry;
  }

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
    return (true, action);
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
    console.log("amountIn", amountIn);
    console.log("amountOut", amountOut);
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
    uint256 amountIn, // collateral tokken
    uint256 amountOut // debt token
  ) internal view returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address collateralRegistry = deptTokenCollateralRegistry[debtToken];

    uint256 amountToRedeem = calculateAmountToRedeem(amountOut, debtToken, collateralRegistry);

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
    action.inputAmount = amountIn; // this value is not accurate as of now as it is the target amount and not updated based on what the conversion rate for redemptions is
    action.incentiveBps = ctx.incentiveBps;
    action.data = abi.encode("");
  }

  function calculateAmountToRedeem(
    uint256 targetAmountOutForRedemption,
    address debtToken,
    address collateralRegistry
  ) internal view returns (uint256 amountToRedeem) {
    // TODO: for this calculation we need a parameter uint256 constant REDEMPTION_BETA = 1; from the Constants.sol file
    // Since this value is currently set to 1 we can ignore it but we should add a way of querying it.
    // TODO: this depends on how upgradeability on the liquityV2 contract will be implemented
    // formula for max amount that can be redeemed given the max fee we are willing to pay:
    // amountToRedeem = totalSupply * REDEMPTION_BETA * (maxFee - decayedBaseFee)
    uint256 decayedBaseFee = ICollateralRegistry(collateralRegistry).getRedemptionRateWithDecay();
    uint256 totalDebtTokenSupply = IERC20(debtToken).totalSupply();

    uint256 maxRedemptionFee = deptTokenMaxRedemptionFee[debtToken];
    uint256 maxAmountToRedeem = (totalDebtTokenSupply * (maxRedemptionFee - decayedBaseFee)) / 1e18;

    if (targetAmountOutForRedemption > maxAmountToRedeem) {
      amountToRedeem = maxAmountToRedeem;
    } else {
      amountToRedeem = targetAmountOutForRedemption;
    }
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
