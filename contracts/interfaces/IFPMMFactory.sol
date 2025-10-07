// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IRPoolFactory } from "../swap/router/interfaces/IRPoolFactory.sol";

interface IFPMMFactory is IRPoolFactory {
  /* ========================================== */
  /* ================= Events ================= */
  /* ========================================== */

  /**
   * @notice Emitted when a new FPMM is deployed.
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @param fpmmProxy The address of the deployed FPMM proxy
   * @param fpmmImplementation The address of the deployed FPMM implementation
   */
  event FPMMDeployed(address indexed token0, address indexed token1, address fpmmProxy, address fpmmImplementation);

  /**
   * @notice Emitted when a new FPMM implementation is registered.
   * @param implementation The address of the registered implementation
   */
  event FPMMImplementationRegistered(address indexed implementation);

  /**
   * @notice Emitted when a new FPMM implementation is unregistered.
   * @param implementation The address of the unregistered implementation
   */
  event FPMMImplementationUnregistered(address indexed implementation);

  /**
   * @notice Emitted when the proxy admin is set.
   * @param proxyAdmin The address of the new proxy admin
   */
  event ProxyAdminSet(address indexed proxyAdmin);

  /**
   * @notice Emitted when the oracle adapter address is set.
   * @param oracleAdapter The address of the new oracle adapter contract
   */
  event OracleAdapterSet(address indexed oracleAdapter);

  /**
   * @notice Emitted when the governance address is set.
   * @param governance The address of the new governance contract
   */
  event GovernanceSet(address indexed governance);

  /* ======================================================== */
  /* ==================== View Functions ==================== */
  /* ======================================================== */

  /**
   * @notice Gets the address of the oracle adapter contract.
   * @return The address of the oracle adapter contract
   */
  function oracleAdapter() external view returns (address);

  /**
   * @notice Gets the address of the proxy admin contract.
   * @return The address of the proxy admin contract
   */
  function proxyAdmin() external view returns (address);

  /**
   * @notice Gets the address of the governance contract.
   * @return The address of the governance contract
   */
  function governance() external view returns (address);

  /**
   * @notice Gets the list of deployed FPMM addresses.
   * @return The list of deployed FPMM addresses
   */
  function deployedFPMMAddresses() external view returns (address[] memory);

  /**
   * @notice Checks if a FPMM implementation is registered.
   * @param fpmmImplementation The address of the FPMM implementation
   * @return True if the FPMM implementation is registered, false otherwise
   */
  function isRegisteredImplementation(address fpmmImplementation) external view returns (bool);

  /**
   * @notice Gets the list of registered FPMM implementations.
   * @return The list of registered FPMM implementations
   */
  function registeredImplementations() external view returns (address[] memory);

  /**
   * @notice Sorts two tokens by their address value.
   * @param tokenA The address of the first token
   * @param tokenB The address of the second token
   * @return token0 The address of the first token
   * @return token1 The address of the second token
   */
  function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Initializes the factory with required addresses.
   * @param _oracleAdapter The address of the oracle adapter contract
   * @param _proxyAdmin The address of the proxy admin contract
   * @param _governance The address of the governance contract
   * @param _fpmmImplementation The address of the FPMM implementation
   */
  function initialize(
    address _oracleAdapter,
    address _proxyAdmin,
    address _governance,
    address _fpmmImplementation
  ) external;

  /**
   * @notice Sets the address of the oracle adapter contract.
   * @param _oracleAdapter The new address of the oracle adapter contract
   */
  function setOracleAdapter(address _oracleAdapter) external;

  /**
   * @notice Sets the address of the proxy admin contract.
   * @param _proxyAdmin The new address of the proxy admin contract
   */
  function setProxyAdmin(address _proxyAdmin) external;

  /**
   * @notice Sets the address of the governance contract.
   * @param _governance The new address of the governance contract
   */
  function setGovernance(address _governance) external;

  /**
   * @notice Registers a new FPMM implementation address.
   * @param fpmmImplementation The FPMM implementation address to register
   */
  function registerFPMMImplementation(address fpmmImplementation) external;

  /**
   * @notice Unregisters a FPMM implementation address.
   * @param fpmmImplementation The FPMM implementation address to unregister
   * @param index The index of the FPMM implementation to unregister
   */
  function unregisterFPMMImplementation(address fpmmImplementation, uint256 index) external;

  /**
   * @notice Deploys a new FPMM for a token pair using the default parameters.
   * @param fpmmImplementation The address of the FPMM implementation
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @param referenceRateFeedID The address of the reference rate feed
   * @return proxy The address of the deployed FPMM proxy
   */
  function deployFPMM(
    address fpmmImplementation,
    address token0,
    address token1,
    address referenceRateFeedID
  ) external returns (address proxy);

  /**
   * @notice Deploys a new FPMM for a token pair using custom parameters.
   * @param fpmmImplementation The address of the FPMM implementation
   * @param customOracleAdapter The address of the custom oracle adapter contract
   * @param customProxyAdmin The address of the custom proxy admin contract
   * @param customGovernance The address of the custom governance contract
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @param referenceRateFeedID The address of the reference rate feed
   * @return proxy The address of the deployed FPMM proxy
   */
  function deployFPMM(
    address fpmmImplementation,
    address customOracleAdapter,
    address customProxyAdmin,
    address customGovernance,
    address token0,
    address token1,
    address referenceRateFeedID
  ) external returns (address proxy);
}
