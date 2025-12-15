// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { IRPoolFactory } from "../swap/router/interfaces/IRPoolFactory.sol";

interface IVirtualPoolFactory is IRPoolFactory {
  /* ========================================== */
  /* ================= Errors ================= */
  /* ========================================== */

  /// @dev Used when the provided Exchange Provider is invalid.
  error InvalidExchangeProvider();

  /// @dev Used when the provided Exchange ID is invalid.
  error InvalidExchangeId();

  /// @dev Used when trying to deploy a VirtualPool for a pair that already has one.
  error VirtualPoolAlreadyExistsForThisPair();

  /// @dev Used when the CREATEX bytecode hash doesn't match the expected value.
  error InvalidCreateXBytecode();

  /// @dev Used when trying to deprecate a pool that doesn't exist.
  error PoolNotFound();

  /// @dev Used when trying to deprecate a pool that is already deprecated.
  error PoolAlreadyDeprecated();

  /* ========================================== */
  /* ================= Events ================= */
  /* ========================================== */

  /**
   * @notice Emitted when a new VirtualPool is deployed.
   * @param pool The address of the deployed VirtualPool
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   */
  event VirtualPoolDeployed(address indexed pool, address indexed token0, address indexed token1);

  /**
   * @notice Emitted when a pool is deprecated.
   * @param pool The address of the deprecated pool
   */
  event PoolDeprecated(address indexed pool);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Deploys a virtual pool contract.
   * @param exchangeProvider Address of the Exchange Provider.
   * @param exchangeId Exchange ID for this pair.
   * @return pool Address of the deployed pool.
   */
  function deployVirtualPool(address exchangeProvider, bytes32 exchangeId) external returns (address pool);

  /**
   * @notice Deprecates a VirtualPool.
   * @param pool The address of the pool to deprecate.
   */
  function deprecatePool(address pool) external;

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  /**
   * @notice Returns all non-deprecated pools that have been deployed.
   * @return An array of all active pool addresses.
   */
  function getAllPools() external view returns (address[] memory);

  /**
   * @notice Checks if a pool is deprecated.
   * @param pool The address of the pool to check.
   * @return True if the pool is deprecated, false otherwise.
   */
  function isPoolDeprecated(address pool) external view returns (bool);
}
