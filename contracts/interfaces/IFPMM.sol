// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IFPMM {
  /// @notice Called on pool creation by PoolFactory
  /// @param _token0 Address of token0
  /// @param _token1 Address of token1
  function initialize(address _token0, address _token1) external;
}
