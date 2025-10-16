// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { ILiquidityStrategy } from "./ILiquidityStrategy.sol";
import { LiquidityTypes as LQ } from "../libraries/LiquidityTypes.sol";

interface ICDPLiquidityStrategy is ILiquidityStrategy {
  error CDPLiquidityStrategy_InvalidPool();
  error CDPLiquidityStrategy_InvalidSender();
  error CDPLiquidityStrategy_InvalidSource();
  error CDPLiquidityStrategy_PoolNotTrusted();

  /**
   * @notice Returns whether a pool is trusted
   * @param pool The address of the pool
   * @return True if the pool is trusted, false otherwise
   */
  function trustedPools(address pool) external view returns (bool);

  /**
   * @notice Sets whether a pool is trusted
   * @param pool The address of the pool
   * @param isTrusted True if the pool is trusted, false otherwise
   */
  function setTrustedPool(address pool, bool isTrusted) external;

  /**
   * @notice Executes a liquidity action
   * @param action The action to execute
   * @return ok True if execution succeeded
   */
  function execute(LQ.Action memory action) external returns (bool ok);

  /**
   * @notice Handles the callback from the FPMM
   * @param sender The address of the sender
   * @param amount0Out The amount of token0 to send out
   * @param amount1Out The amount of token1 to send out
   * @param data The data to pass to the callback
   */
  function hook(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external;
}
