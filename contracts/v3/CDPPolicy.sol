// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { ICDPPolicy } from "./Interfaces/ICDPPolicy.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";

/**
 * @title CDPPolicy
 * @notice Implements a policy that determines the action to take based on the pool price and the oracle price.
 */
contract CDPPolicy is ICDPPolicy, Ownable {
  /* ========== VARIABLES ========== */

  /// @inheritdoc ICDPPolicy
  mapping(address => address) public deptTokenStabilityPool;

  /// @inheritdoc ICDPPolicy
  mapping(address => address) public deptTokenCollateralRegistry;

  // For now stored in a mapping as it is not readable from the collateral registry
  /// @inheritdoc ICDPPolicy
  mapping(address => uint256) public deptTokenRedemptionBeta;

  /// @inheritdoc ICDPPolicy
  mapping(address => uint256) public deptTokenStabilityPoolPercentage;

  /// @inheritdoc ICDPPolicy
  uint256 public constant BPS_TO_FEE_SCALER = 1e14;

  /// @inheritdoc ICDPPolicy
  uint256 public constant BPS_DENOMINATOR = 10_000;

  /* ========== INITIALIZATION ========== */

  /**
   * @notice Constructor
   * @param initialOwner The owner of the policy
   * @param debtTokens The addresses of the debt tokens
   * @param stabilityPools The addresses of the stability pools
   * @param collateralRegistries The addresses of the collateral registries
   * @param redemptionBetas The redemption betas
   * @param stabilityPoolPercentages The stability pool percentages
   */
  constructor(
    address initialOwner,
    address[] memory debtTokens,
    address[] memory stabilityPools,
    address[] memory collateralRegistries,
    uint256[] memory redemptionBetas,
    uint256[] memory stabilityPoolPercentages
  ) {
    Ownable(initialOwner);
    if (
      debtTokens.length != stabilityPools.length ||
      debtTokens.length != collateralRegistries.length ||
      debtTokens.length != redemptionBetas.length ||
      debtTokens.length != stabilityPoolPercentages.length
    ) revert CDPPolicy_ConstructorArrayLengthMismatch();

    for (uint256 i = 0; i < debtTokens.length; i++) {
      _setDeptTokenStabilityPool(debtTokens[i], stabilityPools[i]);
      _setDeptTokenCollateralRegistry(debtTokens[i], collateralRegistries[i]);
      _setDeptTokenRedemptionBeta(debtTokens[i], redemptionBetas[i]);
      _setDeptTokenStabilityPoolPercentage(debtTokens[i], stabilityPoolPercentages[i]);
    }
  }

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  /// @inheritdoc ICDPPolicy
  function name() external pure returns (string memory) {
    return "CDPPolicy";
  }

  /* ============================================================ */
  /* ===================== External Functions =================== */
  /* ============================================================ */

  /// @inheritdoc ICDPPolicy
  function setDeptTokenStabilityPool(address debtToken, address stabilityPool) external onlyOwner {
    _setDeptTokenStabilityPool(debtToken, stabilityPool);
  }

  /// @inheritdoc ICDPPolicy
  function setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) external onlyOwner {
    _setDeptTokenCollateralRegistry(debtToken, collateralRegistry);
  }

  /// @inheritdoc ICDPPolicy
  function setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) external onlyOwner {
    _setDeptTokenRedemptionBeta(debtToken, redemptionBeta);
  }

  /// @inheritdoc ICDPPolicy
  function setDeptTokenStabilityPoolPercentage(address debtToken, uint256 stabilityPoolPercentage) external onlyOwner {
    _setDeptTokenStabilityPoolPercentage(debtToken, stabilityPoolPercentage);
  }

  /// @inheritdoc ICDPPolicy
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

  function _setDeptTokenCollateralRegistry(address debtToken, address collateralRegistry) internal {
    deptTokenCollateralRegistry[debtToken] = collateralRegistry;
  }

  function _setDeptTokenRedemptionBeta(address debtToken, uint256 redemptionBeta) internal {
    deptTokenRedemptionBeta[debtToken] = redemptionBeta;
  }

  function _setDeptTokenStabilityPoolPercentage(address debtToken, uint256 stabilityPoolPercentage) internal {
    if (!(0 < stabilityPoolPercentage && stabilityPoolPercentage < BPS_DENOMINATOR))
      revert CDPPolicy_InvalidStabilityPoolPercentage();
    deptTokenStabilityPoolPercentage[debtToken] = stabilityPoolPercentage;
  }

  /**
   * @notice Handles the case where the pool price is above the oracle price
   * calculates the target amount of token1 to be taken out from the pool and the amount of token0
   * to be added to the pool in order to bring the pool price back to the oracle price.
   * Formulas:
   * token1Out = (OD * RN - ON * RD) / (OD * (2 - i))
   * token0In = (token1Out * OD * (1 - i) )/ ON
   *
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @return shouldAct True if the policy should take action, false otherwise.
   * @return action The action to be taken if shouldAct is true.
   */
  function _handlePoolPriceAbove(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleDen * ctx.reserves.reserveNum - ctx.prices.oracleNum * ctx.reserves.reserveDen;
    // slither-disable-start divide-before-multiply
    uint256 denominator = (ctx.prices.oracleDen * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token1Out = (numerator * ctx.token1Dec) / (denominator * 1e18);
    // slither-disable-end divide-before-multiply

    uint256 token0In = LQ.convertWithRateScalingAndFee(
      token1Out,
      ctx.token1Dec,
      ctx.token0Dec,
      ctx.prices.oracleDen,
      ctx.prices.oracleNum,
      LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
      LQ.BASIS_POINTS_DENOMINATOR
    );

    if (ctx.isToken0Debt) {
      action = _handleExpansion(ctx, token0In, token1Out);
      shouldAct = true;
    } else {
      action = _handleContraction(ctx, token1Out);
      shouldAct = true;
    }
    return (shouldAct, action);
  }

  /**
   * @notice Handles the case where the pool price is below the oracle price.
   * Calculates the target amount of token0 to be taken out from the pool and the amount of token1
   * to be added to the pool in order to bring the pool price back to the oracle price.
   * Formulas:
   * token0Out = (ON * RD - OD * RN) / (ON * (2 - i))
   * token1In = (token0Out * ON * (1 - i) )/ OD
   *
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @return shouldAct True if the policy should take action, false otherwise.
   * @return action The action to be taken if shouldAct is true.
   */
  function _handlePoolPriceBelow(
    LQ.Context memory ctx
  ) internal view returns (bool shouldAct, LQ.Action memory action) {
    uint256 numerator = ctx.prices.oracleNum * ctx.reserves.reserveDen - ctx.prices.oracleDen * ctx.reserves.reserveNum;
    // slither-disable-start divide-before-multiply
    uint256 denominator = (ctx.prices.oracleNum * (2 * LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps)) /
      LQ.BASIS_POINTS_DENOMINATOR;

    uint256 token0Out = (numerator * ctx.token0Dec) / (denominator * 1e18);
    // slither-disable-end divide-before-multiply

    uint256 token1In = LQ.convertWithRateScalingAndFee(
      token0Out,
      ctx.token0Dec,
      ctx.token1Dec,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      LQ.BASIS_POINTS_DENOMINATOR - ctx.incentiveBps,
      LQ.BASIS_POINTS_DENOMINATOR
    );

    if (ctx.isToken0Debt) {
      action = _handleContraction(ctx, token0Out);
      shouldAct = true;
    } else {
      action = _handleExpansion(ctx, token1In, token0Out);
      shouldAct = true;
    }

    return (shouldAct, action);
  }

  /**
   * @notice Handles the expansion of the pool, takes collateral from the fpmm and swaps it for
   * debt token from the stability pool. This operation is limited by the available balance in the stability pool.
   * The incentive is paid to the stability pool.
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @param amountIn The target amount of debt token to be taken out from the fpmm
   * @param amountOut The target amount of collateral to be added to the stability pool
   * @return action The action to be taken.
   */
  function _handleExpansion(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view returns (LQ.Action memory action) {
    (address debtToken, address collToken) = ctx.isToken0Debt ? (ctx.token0, ctx.token1) : (ctx.token1, ctx.token0);
    address stabilityPool = deptTokenStabilityPool[debtToken];
    uint256 availableSPAmount = _calculateAvailablePoolBalance(stabilityPool, debtToken);
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

  /**
   * @notice Handles the contraction of the pool, takes debt tokens from the fpmm and redeems them for
   * collateral through the collateral registry. This operation is limited by the Liquityv2 redemption fee.
   * If the redemption fee is larger than the rebalance incentive, less debt will be redeemed.
   * @param ctx The context containing pool, reserves, prices, and other relevant data.
   * @param amountOut The target amount of debt tokens to be redeemed.
   * @return action The action to be taken.
   */
  function _handleContraction(
    LQ.Context memory ctx,
    uint256 amountOut
  ) internal view returns (LQ.Action memory action) {
    address debtToken = ctx.isToken0Debt ? ctx.token0 : ctx.token1;
    address collToken = ctx.isToken0Debt ? ctx.token1 : ctx.token0;
    address collateralRegistry = deptTokenCollateralRegistry[debtToken];
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
    address debtToken
  ) internal view returns (uint256 availableAmount) {
    uint256 stabilityPoolBalance = IERC20(debtToken).balanceOf(stabilityPool);
    uint256 stabilityPoolMinBalance = IStabilityPool(stabilityPool).MIN_BOLD_AFTER_REBALANCE();

    if (stabilityPoolBalance <= stabilityPoolMinBalance) revert CDPPolicy_StabilityPoolBalanceTooLow();

    uint256 stabilityPoolPercentage = (stabilityPoolBalance * deptTokenStabilityPoolPercentage[debtToken]) /
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
    require(maxRedemptionFee > decayedBaseFee, "CDPPolicy: REDEMPTION_FEE_TOO_LARGE");
    uint256 redemptionBeta = deptTokenRedemptionBeta[debtToken];

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
