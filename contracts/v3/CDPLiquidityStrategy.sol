// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { ICDPLiquidityStrategy } from "./Interfaces/ICDPLiquidityStrategy.sol";
import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { LiquidityTypes as LQ } from "./libraries/LiquidityTypes.sol";
import { IFPMM } from "../interfaces/IFPMM.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "bold/Interfaces/ICollateralRegistry.sol";
import { IStabilityPool } from "bold/Interfaces/IStabilityPool.sol";

/**
 * @title CDPLiquidityStrategy
 * @notice Implements a liquidity strategy that sources the StabilityPool for expansions
 * and the redemption mechanism for contractions.
 */
contract CDPLiquidityStrategy is ICDPLiquidityStrategy, Ownable {
  using SafeERC20 for IERC20;

  /* ========== STATE VARIABLES ========== */

  /// @inheritdoc ICDPLiquidityStrategy
  mapping(address => bool) public trustedPools;

  /* ========== INITIALIZATION ========== */

  /**
   * @notice Constructor
   * @param initialOwner The owner of the strategy
   */
  constructor(address initialOwner) {
    Ownable(initialOwner);
  }

  /* ============================================================ */
  /* ===================== External Functions =================== */
  /* ============================================================ */

  /// @inheritdoc ICDPLiquidityStrategy
  function setTrustedPool(address pool, bool isTrusted) external onlyOwner {
    if (pool == address(0)) revert CDPLiquidityStrategy_InvalidPool();
    trustedPools[pool] = isTrusted;
  }

  /// @inheritdoc ICDPLiquidityStrategy
  function execute(LQ.Action memory action) external override returns (bool ok) {
    if (action.liquiditySource != LQ.LiquiditySource.CDP) revert CDPLiquidityStrategy_InvalidSource();
    if (!trustedPools[action.pool]) revert CDPLiquidityStrategy_PoolNotTrusted();

    (address debtToken, address collToken, address liquiditySource) = abi.decode(
      action.data,
      (address, address, address)
    );
    bytes memory hookData = abi.encode(
      action.inputAmount,
      action.incentiveBps,
      action.dir,
      debtToken,
      collToken,
      liquiditySource
    );

    IFPMM(action.pool).rebalance(action.amount0Out, action.amount1Out, hookData);
    return true;
  }

  /// @inheritdoc ICDPLiquidityStrategy
  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
    if (!trustedPools[msg.sender]) revert CDPLiquidityStrategy_PoolNotTrusted();
    if (sender != address(this)) revert CDPLiquidityStrategy_InvalidSender();

    (
      uint256 inputAmount,
      uint256 incentiveBps,
      LQ.Direction dir,
      address debtToken,
      address collToken,
      address liquiditySource
    ) = abi.decode(data, (uint256, uint256, LQ.Direction, address, address, address));
    uint256 amountOut = amount0Out > 0 ? amount0Out : amount1Out;
    if (dir == LQ.Direction.Expand) {
      _handleExpansionCallback(debtToken, collToken, amountOut, inputAmount, liquiditySource);
    } else {
      _handleContractionCallback(collToken, amountOut, inputAmount, incentiveBps, liquiditySource);
    }
  }

  /* ============================================================ */
  /* =================== Internal Functions ===================== */
  /* ============================================================ */

  /**
   * @notice Handles the expansion callback
   * @param debtToken The address of the debt token
   * @param collToken The address of the collateral token
   * @param amountOut The amount of collateral to send to the stability pool
   * @param inputAmount The amount of debt to send to the fpmm
   * @param liquiditySource The address of the liquidity source
   */
  function _handleExpansionCallback(
    address debtToken,
    address collToken,
    uint256 amountOut,
    uint256 inputAmount,
    address liquiditySource
  ) internal {
    // send collateral to stability pool
    IERC20(collToken).safeApprove(liquiditySource, amountOut);
    // swap collateral for debt
    IStabilityPool(liquiditySource).swapCollateralForStable(amountOut, inputAmount);
    // send debt to fpmm
    IERC20(debtToken).safeTransfer(msg.sender, inputAmount);
  }

  /**
   * @notice Handles the contraction callback
   * @param collToken The address of the collateral token
   * @param amountOut The amount of collateral to send to the collateral registry
   * @param inputAmount The amount of debt to send to the fpmm
   * @param incentiveBps The incentive bps
   * @param liquiditySource The address of the liquidity source
   */
  function _handleContractionCallback(
    address collToken,
    uint256 amountOut,
    uint256 inputAmount,
    uint256 incentiveBps,
    address liquiditySource
  ) internal {
    ICollateralRegistry(liquiditySource).redeemCollateral(amountOut, 100, incentiveBps);
    IERC20(collToken).safeTransfer(msg.sender, inputAmount);
  }
}
