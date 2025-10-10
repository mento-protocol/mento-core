// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { LiquidityStrategy } from "./LiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "./interfaces/ICDPLiquidityStrategy.sol";
import { CDPRebalancer } from "./CDPRebalancer.sol";
import { CDPPolicy } from "./CDPPolicy.sol";
import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy is ICDPLiquidityStrategy, LiquidityStrategy, CDPRebalancer, CDPPolicy {
  using LQ for LQ.Context;

  uint256 constant BPS_TO_FEE_SCALER = 1e14;
  uint256 constant BPS_DENOMINATOR = 10_000;

  mapping(address => CDPConfig) private cdpConfigs;

  /// @notice Constructor
  /// @param _initialOwner the initial owner of the contract
  constructor(address _initialOwner) LiquidityStrategy(_initialOwner) {}

  /* ============================================================ */
  /* ==================== External Functions ==================== */
  /* ============================================================ */

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

  function removePool(address pool) external onlyOwner {
    LiquidityStrategy._removePool(pool);
    delete cdpConfigs[pool];
  }

  function setCDPConfig(address pool, CDPConfig calldata config) external onlyOwner {
    _ensurePool(pool);
    cdpConfigs[pool] = config;
  }

  function getCDPConfig(address pool) external view returns (CDPConfig memory) {
    _ensurePool(pool);
    return cdpConfigs[pool];
  }

  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    _ensurePool(msg.sender);
    require(sender == address(this), "CDPLiquidityStrategy: INVALID_SENDER");

    (uint256 inputAmount, uint256 incentiveBps, LQ.Direction dir, address debtToken, address collToken) = abi.decode(
      data,
      (uint256, uint256, LQ.Direction, address, address)
    );
    if (dir == LQ.Direction.Expand) {
      // swap coll for debt in stability pool
      uint256 collAmount = amount0Out > 0 ? amount0Out : amount1Out;
      address stabilityPool = _getStabilityPool(fpmm);
      SafeERC20.safeApprove(IERC20(collToken), stabilityPool, collAmount);
      IStabilityPool(stabilityPool).swapCollateralForStable(collAmount, inputAmount);
      // transfer debt to FPMM
      SafeERC20.safeTransfer(IERC20(debtToken), fpmm, inputAmount);
    } else {
      // redeem debt for coll
      uint256 debtAmount = amount0Out > 0 ? amount0Out : amount1Out;
      address collateralRegistry = _getCollateralRegistry(fpmm);
      ICollateralRegistry(collateralRegistry).redeemCollateral(debtAmount, 100, incentiveBps);

      uint256 collateralBalance = IERC20(collToken).balanceOf(address(this));
      require(collateralBalance >= inputAmount, "CDPLiquidityStrategy: INSUFFICIENT_COLLATERAL_FROM_REDEMPTION");
      // transfer coll to FPMM
      SafeERC20.safeTransfer(IERC20(collToken), fpmm, inputAmount);
    }
  }

  /* =========================================================== */
  /* ==================== Virtual Functions ==================== */
  /* =========================================================== */

  function _buildExpansionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override(LiquidityStrategy, CDPPolicy) returns (LQ.Action memory action) {
    return CDPLSLib.buildExpansionAction(ctx, cdpConfigs[ctx.pool], amountIn, amountOut);
  }

  function _buildContractionAction(
    LQ.Context memory ctx,
    uint256 amountIn,
    uint256 amountOut
  ) internal view override(LiquidityStrategy, CDPPolicy) returns (LQ.Action memory action) {
    return CDPLSLib.buildContractionAction(ctx, cdpConfigs[ctx.pool], amountOut);
  }

  function _execute(
    LQ.Context memory ctx,
    LQ.Action memory action
  ) internal override(LiquidityStrategy, CDPRebalancer) returns (bool) {
    (address debtToken, address collToken) = ctx.tokens();
    bytes memory hookData = abi.encode(action.inputAmount, ctx.incentiveBps, action.dir, debtToken, collToken);
    IFPMM(action.pool).rebalance(action.amount0Out, action.amount1Out, hookData);
    return true;
  }
}
