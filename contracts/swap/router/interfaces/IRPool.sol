// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title IRPool
 * @notice Minimal interface for a Pool that the router can use
 * to swap
 */
interface IRPool {
  /* ========== Events ========== */

  /**
   * @notice Emitted when tokens are swapped
   * @param sender Address that initiated the swap
   * @param amount0In Amount of token0 sent to the pool
   * @param amount1In Amount of token1 sent to the pool
   * @param amount0Out Amount of token0 sent to the receiver
   * @param amount1Out Amount of token1 sent to the receiver
   * @param to Address receiving the output tokens
   */
  event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
  );

  /* ========== View Functions ========== */

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

  /**
   * @notice Returns pool metadata
   * @return dec0 Scaling factor for token0
   * @return dec1 Scaling factor for token1
   * @return r0 Reserve amount of token0
   * @return r1 Reserve amount of token1
   * @return t0 Address of token0
   * @return t1 Address of token1
   */
  function metadata()
    external
    view
    returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1);

  /**
   * @notice Returns addresses of both tokens in the pair
   * @return Address of token0 and token1
   */
  function tokens() external view returns (address, address);

  /**
   * @notice Returns the address of the first token in the pair
   * @return Address of token0
   */
  function token0() external view returns (address);

  /**
   * @notice Returns the address of the second token in the pair
   * @return Address of token1
   */
  function token1() external view returns (address);

  /**
   * @notice Returns the scaling factor for token0 based on its decimals
   * @return Scaling factor for token0
   */
  function decimals0() external view returns (uint256);

  /**
   * @notice Returns the scaling factor for token1 based on its decimals
   * @return Scaling factor for token1
   */
  function decimals1() external view returns (uint256);

  /**
   * @notice Returns the reserve amount of token0
   * @return Reserve amount of token0
   */
  function reserve0() external view returns (uint256);

  /**
   * @notice Returns the reserve amount of token1
   * @return Reserve amount of token1
   */
  function reserve1() external view returns (uint256);

  /**
   * @notice Returns the protocol fee in basis points (1 basis point = .01%)
   * @return Protocol fee in basis points
   */
  function protocolFee() external view returns (uint256);
}
