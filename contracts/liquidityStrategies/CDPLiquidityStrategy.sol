// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICollateralRegistry } from "bold/src/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "bold/src/Interfaces/IStabilityPool.sol";

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "../interfaces/ICDPLiquidityStrategy.sol";
import { LiquidityStrategyTypes as LQ } from "../libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy is ICDPLiquidityStrategy, LiquidityStrategy {
  using SafeERC20 for IERC20;
  using LQ for LQ.Context;

  /// @dev Tolerance for the redemption operation which is
  /// subsidized by this contract.
  uint256 public immutable REDEMPTION_SHORTFALL_TOLERANCE;

  mapping(address => CDPConfig) private cdpConfigs;

  /* ============================================================ */
  /* ======================= Constructor ======================== */
  /* ============================================================ */

  /**
   * @notice Disables initializers on implementation contracts.
   * @param disable Set to true to disable initializers (for proxy pattern).
   */
  constructor(bool disable, uint256 _redemptionShortfallTolerance) LiquidityStrategy(disable) {
    REDEMPTION_SHORTFALL_TOLERANCE = _redemptionShortfallTolerance;
  }

  /**
   * @notice Initializes the CDPLiquidityStrategy contract
   * @param _initialOwner The initial owner of the contract
   */
  function initialize(address _initialOwner) public initializer {
    __LiquidityStrategy_init(_initialOwner);
  }

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

  // @inheritdoc ICDPLiquidityStrategy
  function addPool(AddPoolParams calldata params, CDPConfig calldata config) external onlyOwner {
    if (!(0 < config.stabilityPoolPercentage && config.stabilityPoolPercentage < LQ.BPS_DENOMINATOR))
      revert CDPLS_INVALID_STABILITY_POOL_PERCENTAGE();
    if (config.collateralRegistry == address(0)) revert CDPLS_COLLATERAL_REGISTRY_IS_ZERO();
    if (config.stabilityPool == address(0)) revert CDPLS_STABILITY_POOL_IS_ZERO();

    LiquidityStrategy._addPool(params);
    cdpConfigs[params.pool] = config;
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
    uint256 availableDebtToken = _calculateAvailableDebtInSP(cdpConfigs[ctx.pool]);

    if (idealDebtToExpand > availableDebtToken) {
      debtToExpand = availableDebtToken;

      uint256 combinedFees = LQ.combineFees(
        ctx.incentives.protocolIncentiveExpansion,
        ctx.incentives.liquiditySourceIncentiveExpansion
      );

      collateralToPay = ctx.convertToCollateralWithFee(debtToExpand, LQ.FEE_DENOMINATOR, combinedFees);
    } else {
      debtToExpand = idealDebtToExpand;
      collateralToPay = idealCollateralToPay;
    }

    return (debtToExpand, collateralToPay);
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
    PoolConfig memory config = poolConfigs[pool];

    // slither-disable-next-line uninitialized-local
    uint256 protocolIncentive;

    if (cb.dir == LQ.Direction.Expand) {
      uint256 collAmount = amount0Out > 0 ? amount0Out : amount1Out;

      // transfer protocol incentive to protocol fee recipient
      if (config.protocolIncentiveExpansion > 0) {
        protocolIncentive = (collAmount * config.protocolIncentiveExpansion) / LQ.FEE_DENOMINATOR;
        _transferRebalanceIncentive(cb.collToken, protocolIncentive, config.protocolFeeRecipient);
      }

      // swap collateral for debt in stability pool
      address stabilityPool = cdpConfigs[pool].stabilityPool;
      IERC20(cb.collToken).safeApprove(stabilityPool, collAmount - protocolIncentive);
      IStabilityPool(stabilityPool).swapCollateralForStable(collAmount - protocolIncentive, cb.amountOwedToPool);

      // Transfer debt to FPMM
      IERC20(cb.debtToken).safeTransfer(pool, cb.amountOwedToPool);
    } else {
      uint256 collateralBalanceBefore = IERC20(cb.collToken).balanceOf(address(this));
      uint256 debtAmount = amount0Out > 0 ? amount0Out : amount1Out;

      // transfer protocol incentive to protocol fee recipient
      if (config.protocolIncentiveContraction > 0) {
        protocolIncentive = (debtAmount * config.protocolIncentiveContraction) / LQ.FEE_DENOMINATOR;
        _transferRebalanceIncentive(cb.debtToken, protocolIncentive, config.protocolFeeRecipient);
      }

      address collateralRegistry = cdpConfigs[pool].collateralRegistry;
      uint256 maxIterations = cdpConfigs[pool].maxIterations;
      ICollateralRegistry(collateralRegistry).redeemCollateralRebalancing(
        debtAmount - protocolIncentive,
        maxIterations,
        config.liquiditySourceIncentiveContraction
      );

      uint256 collateralBalanceAfter = IERC20(cb.collToken).balanceOf(address(this));
      uint256 collateralReceived = collateralBalanceAfter - collateralBalanceBefore;

      // @dev Redemption may return slightly more or less collateral than expected due to
      // precision loss. Surplus is kept to offset future shortfalls; shortfalls are
      // subsidized from contract balance (up to REDEMPTION_SHORTFALL_TOLERANCE).
      if (collateralReceived < cb.amountOwedToPool) {
        uint256 shortfall = cb.amountOwedToPool - collateralReceived;
        if (shortfall > REDEMPTION_SHORTFALL_TOLERANCE) {
          revert CDPLS_REDEMPTION_SHORTFALL_TOO_LARGE(shortfall);
        }
        if (IERC20(cb.collToken).balanceOf(address(this)) < cb.amountOwedToPool) {
          revert CDPLS_OUT_OF_FUNDS_FOR_REDEMPTION_SUBSIDY();
        }
        emit RedemptionShortfallSubsidized(pool, shortfall);
      }

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
   * @return availableAmount The amount of debt tokens available for expansion
   */
  function _calculateAvailableDebtInSP(CDPConfig memory cdpConfig) private view returns (uint256 availableAmount) {
    IStabilityPool stabilityPool = IStabilityPool(cdpConfig.stabilityPool);
    uint256 stabilityPoolBalance = stabilityPool.getTotalBoldDeposits();
    uint256 stabilityPoolMinBalance = stabilityPool.systemParams().MIN_BOLD_AFTER_REBALANCE();
    if (stabilityPoolBalance <= stabilityPoolMinBalance) revert CDPLS_STABILITY_POOL_BALANCE_TOO_LOW();

    uint256 targetDebtToExtract = (stabilityPoolBalance * cdpConfig.stabilityPoolPercentage) / LQ.BPS_DENOMINATOR;
    uint256 maxDebtExtractable = stabilityPoolBalance - stabilityPoolMinBalance;

    availableAmount = targetDebtToExtract > maxDebtExtractable ? maxDebtExtractable : targetDebtToExtract;
  }
}
