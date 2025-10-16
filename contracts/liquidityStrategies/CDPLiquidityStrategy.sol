// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "../interfaces/ICDPLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "../libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy is ICDPLiquidityStrategy, LiquidityStrategy {
  using SafeERC20 for IERC20;
  using LQ for LQ.Context;

  uint256 public constant BPS_TO_FEE_SCALER = 1e14;
  uint256 public constant BPS_DENOMINATOR = 10_000;

  mapping(address => CDPConfig) private cdpConfigs;

  /* ============================================================ */
  /* ======================= Constructor ======================== */
  /* ============================================================ */

  /**
   * @notice Constructor
   * @param _initialOwner The initial owner of the contract
   */
  constructor(address _initialOwner) LiquidityStrategy(_initialOwner) {}

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  /// @inheritdoc ICDPLiquidityStrategy
  function addPool(
    address pool,
    address debtToken,
    uint64 cooldown,
    uint32 incentiveBps,
    address stabilityPool,
    address collateralRegistry,
    uint256 redemptionBeta,
    uint256 stabilityPoolPercentage
  ) external onlyOwner {
    if (!(0 < stabilityPoolPercentage && stabilityPoolPercentage < BPS_DENOMINATOR))
      revert CDPLS_INVALID_STABILITY_POOL_PERCENTAGE();
    if (collateralRegistry == address(0)) revert CDPLS_COLLATERAL_REGISTRY_IS_ZERO();
    if (stabilityPool == address(0)) revert CDPLS_STABILITY_POOL_IS_ZERO();

    LiquidityStrategy._addPool(pool, debtToken, cooldown, incentiveBps);
    cdpConfigs[pool] = CDPConfig({
      stabilityPool: stabilityPool,
      collateralRegistry: collateralRegistry,
      redemptionBeta: redemptionBeta,
      stabilityPoolPercentage: stabilityPoolPercentage
    });
  }

  /// @inheritdoc ICDPLiquidityStrategy
  function removePool(address pool) external onlyOwner {
    LiquidityStrategy._removePool(pool);
    delete cdpConfigs[pool];
  }

  /// @inheritdoc ICDPLiquidityStrategy
  function setCDPConfig(address pool, CDPConfig calldata config) external onlyOwner {
    _ensurePool(pool);
    cdpConfigs[pool] = config;
  }

  /// @inheritdoc ICDPLiquidityStrategy
  function getCDPConfig(address pool) external view returns (CDPConfig memory) {
    _ensurePool(pool);
    return cdpConfigs[pool];
  }

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  /**
   * @notice Clamps expansion amounts based on stability pool balance
   * @dev Checks available balance in the stability pool and adjusts expansion amount if needed
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtToExpand The calculated ideal amount of debt tokens to swap from stability pool
   * @param idealCollateralToPay The calculated ideal amount of collateral to send to stability pool
   * @return debtToExpand The actual debt amount to expand (limited by stability pool balance)
   * @return collateralToPay The actual collateral amount to receive (adjusted proportionally)
   */
  function _clampExpansion(
    LQ.Context memory ctx,
    uint256 idealDebtToExpand,
    uint256 idealCollateralToPay
  ) internal view override returns (uint256 debtToExpand, uint256 collateralToPay) {
    uint256 availableDebtToken = _calculateAvailableDebtInSP(cdpConfigs[ctx.pool], ctx.debtToken());

    if (idealDebtToExpand > availableDebtToken) {
      debtToExpand = availableDebtToken;

      collateralToPay = ctx.convertToCollateralWithFee(
        debtToExpand,
        BPS_DENOMINATOR,
        BPS_DENOMINATOR - ctx.incentiveBps
      );
    } else {
      debtToExpand = idealDebtToExpand;
      collateralToPay = idealCollateralToPay;
    }

    return (debtToExpand, collateralToPay);
  }

  /**
   * @notice Clamps contraction amounts based on redemption fee constraints
   * @dev Calculates max redeemable amount based on current redemption fees and adjusts if needed
   * @param ctx The liquidity context containing pool state and configuration
   * @param idealDebtToContract The calculated ideal amount of debt tokens to redeem
   * @return debtToContract The actual debt amount to contract (limited by redemption fee)
   * @return collateralToReceive The actual collateral amount to send (adjusted based on redemption fee)
   */
  function _clampContraction(
    LQ.Context memory ctx,
    uint256 idealDebtToContract,
    uint256 // idealCollateralToReceive - used in other implementations
  ) internal view override returns (uint256 debtToContract, uint256 collateralToReceive) {
    (debtToContract, collateralToReceive) = _calculateMaxRedeemableDebt(ctx, cdpConfigs[ctx.pool], idealDebtToContract);
    return (debtToContract, collateralToReceive);
  }

  /* ============================================================ */
  /* ================= Callback Implementation ================== */
  /* ============================================================ */

  /**
   * @notice Handles the rebalance callback by interacting with CDP protocol contracts
   * @dev For expansions, swaps collateral for stable via stability pool
   *      For contractions, redeems stable for collateral via collateral registry
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
      // Expansion: swap collateral for debt in stability pool
      uint256 collAmount = amount0Out > 0 ? amount0Out : amount1Out;
      address stabilityPool = cdpConfigs[pool].stabilityPool;
      IERC20(cb.collToken).safeApprove(stabilityPool, collAmount);
      IStabilityPool(stabilityPool).swapCollateralForStable(collAmount, cb.amountOwedToPool);
      // Transfer debt to FPMM
      IERC20(cb.debtToken).safeTransfer(pool, cb.amountOwedToPool);
    } else {
      // Contraction: redeem debt for collateral
      uint256 debtAmount = amount0Out > 0 ? amount0Out : amount1Out;
      address collateralRegistry = cdpConfigs[pool].collateralRegistry;
      ICollateralRegistry(collateralRegistry).redeemCollateral(debtAmount, 100, cb.incentiveBps);

      uint256 collateralBalance = IERC20(cb.collToken).balanceOf(address(this));
      if (collateralBalance < cb.amountOwedToPool) revert CDPLS_INSUFFICIENT_COLLATERAL_FROM_REDEMPTION();
      // Transfer collateral to FPMM
      IERC20(cb.collToken).safeTransfer(pool, cb.amountOwedToPool);
    }
  }

  /* ============================================================ */
  /* =================== Private Functions ====================== */
  /* ============================================================ */

  /**
   * @notice Calculates the available balance in the stability pool for rebalancing
   * @dev Takes into account minimum balance requirements and configured percentage limits
   * @param cdpConfig The CDP configuration for the pool
   * @param debtToken The address of the debt token
   * @return availableAmount The amount of debt tokens available for expansion
   */
  function _calculateAvailableDebtInSP(
    CDPConfig storage cdpConfig,
    address debtToken
  ) private view returns (uint256 availableAmount) {
    uint256 stabilityPoolBalance = IERC20(debtToken).balanceOf(cdpConfig.stabilityPool);
    uint256 stabilityPoolMinBalance = IStabilityPool(cdpConfig.stabilityPool).MIN_BOLD_AFTER_REBALANCE();

    if (stabilityPoolBalance <= stabilityPoolMinBalance) revert CDPLS_STABILITY_POOL_BALANCE_TOO_LOW();

    uint256 stabilityPoolAvailable = (stabilityPoolBalance * cdpConfig.stabilityPoolPercentage) / BPS_DENOMINATOR;

    uint256 availableAmountAfterMinBalance = stabilityPoolBalance - stabilityPoolMinBalance;
    availableAmount = stabilityPoolAvailable > availableAmountAfterMinBalance
      ? availableAmountAfterMinBalance
      : stabilityPoolAvailable;
  }

  /**
   * @notice Calculates the maximum amount that can be redeemed given current redemption fees
   * @dev Uses the redemption fee formula to determine max redeemable amount within incentive constraints
   * @param ctx The liquidity context
   * @param cdpConfig The CDP configuration for the pool
   * @param targetContractionAmount The desired amount of debt tokens to redeem
   * @return contractionAmount The actual amount of debt tokens to redeem (may be lower than target)
   * @return collateralReceived The amount of collateral that will be received
   */
  function _calculateMaxRedeemableDebt(
    LQ.Context memory ctx,
    CDPConfig storage cdpConfig,
    uint256 targetContractionAmount
  ) private view returns (uint256 contractionAmount, uint256 collateralReceived) {
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

    uint256 redemptionFee = decayedBaseFee +
      (contractionAmount * 1e18 * cdpConfig.redemptionBeta) /
      totalDebtTokenSupply;

    // redemption fee is capped at 100%
    redemptionFee = redemptionFee > 1e18 ? 1e18 : redemptionFee;

    collateralReceived = ctx.convertToCollateralWithFee(contractionAmount, 1e18 - redemptionFee, 1e18);
  }
}
