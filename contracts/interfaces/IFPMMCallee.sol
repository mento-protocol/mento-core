// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title Fixed Price Market Maker Callee Interface
 * @author Mento Labs
 * @notice Interface for contracts that can be called during FPMM swaps
 * @dev This interface allows for callback functionality when interacting with FPMM.
 * It enables flash swaps and other advanced trading strategies where a contract
 * can be notified after receiving tokens but before the swap completes.
 */
interface IFPMMCallee {
  /**
   * @notice Callback function for FPMM swap operations
   * @dev Called after tokens have been transferred from FPMM but before swap validation checks
   * @param sender The original address that initiated the swap
   * @param amount0 The amount of token0 received by the callee
   * @param amount1 The amount of token1 received by the callee
   * @param data Additional data forwarded from the swap call
   */
  function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
