// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

/**
 * @title IRouterFactory
 * @notice Minimal interface for a Factory that the router can use to access pools
 */
interface IRPoolFactory {
  /**
   * @notice Gets the precomputed or current proxy address for a token pair.
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @return The address of the FPMM proxy for the token pair
   */
  function getOrPrecomputeProxyAddress(address token0, address token1) external view returns (address);

  /// @notice Checks if a pool is a valid pool created by this factory.
  /// @param pool The address of the pool
  /// @return True if the pool exists, false otherwise
  function isPool(address pool) external view returns (bool);

  /// @notice Gets the address of the deployed FPMM for a token pair.
  /// @param token0 The address of the first token
  /// @param token1 The address of the second token
  /// @return The address of the deployed FPMM for the token pair
  function getPool(address token0, address token1) external view returns (address);
}
