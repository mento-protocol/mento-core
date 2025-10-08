// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { LiquidityStrategyTypes as LQ } from "./libraries/LiquidityStrategyTypes.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";

interface IStabilityPool {
  function swapCollateralForStable(uint256 amountStableOut, uint256 amountCollIn) external;
}

abstract contract CDPRebalancer is Ownable {
  using LQ for LQ.Context;

  /* =========================================================== */
  /* =================== Virtual Functions ===================== */
  /* =========================================================== */

  function _ensurePool(address pool) internal view virtual;

  function _getStabilityPool(address pool) internal view virtual returns (address);

  function _getCollateralRegistry(address pool) internal view virtual returns (address);

  /* =========================================================== */
  /* ================== External Functions ===================== */
  /* =========================================================== */

  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    _ensurePool(msg.sender);
    require(sender == address(this), "CDPLiquidityStrategy: INVALID_SENDER");

    (uint256 inputAmount, uint256 incentiveBps, LQ.Direction dir, address debtToken, address collToken) = abi.decode(
      data,
      (uint256, uint256, LQ.Direction, address, address)
    );
    if (dir == LQ.Direction.Expand) {
      _handleExpansionCallback(msg.sender, debtToken, collToken, amount0Out, amount1Out, inputAmount);
    } else {
      _handleContractionCallback(msg.sender, collToken, amount0Out, amount1Out, inputAmount, incentiveBps);
    }
  }

  /* =========================================================== */
  /* ================== Internal Functions ===================== */
  /* =========================================================== */

  function _execute(LQ.Context memory ctx, LQ.Action memory action) internal virtual returns (bool ok) {
    (address debtToken, address collToken) = ctx.tokens();
    bytes memory hookData = abi.encode(action.inputAmount, ctx.incentiveBps, action.dir, debtToken, collToken);
    IFPMM(action.pool).rebalance(action.amount0Out, action.amount1Out, hookData);
    return true;
  }

  function _handleExpansionCallback(
    address fpmm,
    address debtToken,
    address collToken,
    uint256 amount0Out,
    uint256 amount1Out,
    uint256 inputAmount
  ) internal {
    uint256 collAmount = amount0Out > 0 ? amount0Out : amount1Out;
    address stabilityPool = _getStabilityPool(fpmm);
    SafeERC20.safeApprove(IERC20(collToken), stabilityPool, collAmount);
    IStabilityPool(stabilityPool).swapCollateralForStable(collAmount, inputAmount);
    SafeERC20.safeTransfer(IERC20(debtToken), fpmm, inputAmount);
  }

  function _handleContractionCallback(
    address fpmm,
    address collToken,
    uint256 amount0Out,
    uint256 amount1Out,
    uint256 inputAmount,
    uint256 incentiveBps
  ) internal {
    uint256 debtAmount = amount0Out > 0 ? amount0Out : amount1Out;
    address collateralRegistry = _getCollateralRegistry(fpmm);
    ICollateralRegistry(collateralRegistry).redeemCollateral(debtAmount, 100, incentiveBps);

    uint256 collateralBalance = IERC20(collToken).balanceOf(address(this));
    require(collateralBalance >= inputAmount, "CDPLiquidityStrategy: INSUFFICIENT_COLLATERAL_FROM_REDEMPTION");
    SafeERC20.safeTransfer(IERC20(collToken), fpmm, inputAmount);
  }
}
