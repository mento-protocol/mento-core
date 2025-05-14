// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

interface IFPMMFactory {
  /* ========================================== */
  /* ================= Events ================= */
  /* ========================================== */

  /**
   * @notice Emitted when a new FPMM is deployed.
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @param fpmm The address of the deployed FPMM
   */
  event FPMMDeployed(address indexed token0, address indexed token1, address fpmm);

  /**
   * @notice Emitted when the FPMM implementation is deployed.
   * @param implementation The address of the deployed implementation
   */
  event FPMMImplementationDeployed(address indexed implementation);

  /**
   * @notice Emitted when the proxy admin is set.
   * @param proxyAdmin The address of the new proxy admin
   */
  event ProxyAdminSet(address indexed proxyAdmin);

  /**
   * @notice Emitted when the sorted oracles address is set.
   * @param sortedOracles The address of the new sorted oracles contract
   */
  event SortedOraclesSet(address indexed sortedOracles);

  /**
   * @notice Emitted when the breaker box address is set.
   * @param breakerBox The address of the new breaker box contract
   */
  event BreakerBoxSet(address indexed breakerBox);

  /**
   * @notice Emitted when the governance address is set.
   * @param governance The address of the new governance contract
   */
  event GovernanceSet(address indexed governance);

  /* ======================================================== */
  /* ==================== View Functions ==================== */
  /* ======================================================== */

  /**
   * @notice Gets the precomputed or current implementation address.
   * @return The address of the FPMM implementation
   */
  function getOrPrecomputeImplementationAddress() external view returns (address);

  /**
   * @notice Gets the precomputed or current proxy address for a token pair.
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @return The address of the FPMM proxy for the token pair
   */
  function getOrPrecomputeProxyAddress(address token0, address token1) external view returns (address);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Initializes the factory with required addresses.
   * @param _sortedOracles The address of the sorted oracles contract
   * @param _proxyAdmin The address of the proxy admin contract
   * @param _breakerBox The address of the breaker box contract
   * @param _governance The address of the governance contract
   */
  function initialize(address _sortedOracles, address _proxyAdmin, address _breakerBox, address _governance) external;

  /**
   * @notice Sets the address of the sorted oracles contract.
   * @param _sortedOracles The new address of the sorted oracles contract
   */
  function setSortedOracles(address _sortedOracles) external;

  /**
   * @notice Sets the address of the proxy admin contract.
   * @param _proxyAdmin The new address of the proxy admin contract
   */
  function setProxyAdmin(address _proxyAdmin) external;

  /**
   * @notice Sets the address of the breaker box contract.
   * @param _breakerBox The new address of the breaker box contract
   */
  function setBreakerBox(address _breakerBox) external;

  /**
   * @notice Sets the address of the governance contract.
   * @param _governance The new address of the governance contract
   */
  function setGovernance(address _governance) external;

  /**
   * @notice Deploys a new FPMM for a token pair.
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @return implementation The address of the FPMM implementation
   * @return proxy The address of the deployed FPMM proxy
   */
  function deployFPMM(address token0, address token1) external returns (address implementation, address proxy);
}
