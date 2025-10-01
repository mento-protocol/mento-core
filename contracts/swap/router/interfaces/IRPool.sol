// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title IRPool
 * @notice Minimal interface for a Pool that the router can use
 * to swap
 */
interface IRPool {
  /**
   * @notice Calculates output amount for a given input
   * @param amountIn Input amount
   * @param tokenIn Address of input token
   * @return amountOut Output amount after fees
   */
  function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256 amountOut);

  /**
   * @notice Swaps tokens
   * @param amount0Out Amount of token0 to output
   * @param amount1Out Amount of token1 to output
   * @param to Address receiving output tokens
   * @param data Optional callback data
   */
  function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

  /// @notice Returns current reserves and timestamp
  /// @return _reserve0 Current reserve of token0
  /// @return _reserve1 Current reserve of token1
  /// @return _blockTimestampLast Timestamp of last reserve update
  function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast);
}
