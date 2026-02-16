// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { IRPoolFactory } from "../swap/router/interfaces/IRPoolFactory.sol";
import { IFPMM } from "./IFPMM.sol";

interface IFPMMFactory is IRPoolFactory {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  // @notice Throw when the CREATEX bytecode hash does not match the expected hash
  error CreateXBytecodeHashMismatch();
  // @notice Throw when trying to set a zero address as a contract address
  error ZeroAddress();
  // @notice Throw when trying to sort identical token addresses
  error IdenticalTokenAddresses();
  // @notice Throw when trying to sort tokens with a zero address as one of the tokens
  error SortTokensZeroAddress();
  // @notice Throw when trying to deploy an fpmm with a zero address as the oracle adapter
  error InvalidOracleAdapter();
  // @notice Throw when trying to deploy an fpmm with a zero address as the proxy admin
  error InvalidProxyAdmin();
  // @notice Throw when trying to deploy an fpmm with a zero address as the owner
  error InvalidOwner();
  // @notice Throw when trying to deploy an fpmm with a zero address as the reference rate feed id
  error InvalidReferenceRateFeedID();
  // @notice Throw when trying to deploy an fpmm for a token pair that already exists
  error PairAlreadyExists();
  // @notice Throw when trying to do an operation with an fpmm implementation that is not registered
  error ImplementationNotRegistered();
  // @notice Throw when trying to register an fpmm implementation that is already registered
  error ImplementationAlreadyRegistered();
  // @notice Throw when trying to unregister an fpmm implementation with an index that is out of bounds
  error IndexOutOfBounds();
  // @notice Throw when trying to unregister an fpmm implementation with an index that does not match the implementation
  error ImplementationIndexMismatch();
  // @notice Throw when trying to set a fee that is too high
  error FeeTooHigh();
  // @notice Throw when trying to set a rebalance incentive that is too high
  error RebalanceIncentiveTooHigh();
  // @notice Throw when trying to set a rebalance threshold that is too high
  error RebalanceThresholdTooHigh();

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

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
   * @notice Emitted when the default parameters are set.
   * @param defaultParams The new default parameters
   */
  event DefaultParamsSet(IFPMM.FPMMParams defaultParams);

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */

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
   * @notice Gets the default parameters for deployed FPMMs.
   * @return The default parameters for deployed FPMMs
   */
  function defaultParams() external view returns (IFPMM.FPMMParams memory);

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
   * @param _owner The address of the owner
   * @param _fpmmImplementation The address of the FPMM implementation
   * @param _defaultParams The default parameters for deployed FPMMs
   */
  function initialize(
    address _oracleAdapter,
    address _proxyAdmin,
    address _owner,
    address _fpmmImplementation,
    IFPMM.FPMMParams calldata _defaultParams
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
   * @notice Sets the default parameters for deployed FPMMs.
   * @param _defaultParams The new default parameters for deployed FPMMs
   */
  function setDefaultParams(IFPMM.FPMMParams calldata _defaultParams) external;

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
   * @param invertRateFeed Wether to invert the rate feed so that the base is asset0 and quote is asset1
   * @return proxy The address of the deployed FPMM proxy
   */
  function deployFPMM(
    address fpmmImplementation,
    address token0,
    address token1,
    address referenceRateFeedID,
    bool invertRateFeed
  ) external returns (address proxy);

  /**
   * @notice Deploys a new FPMM for a token pair using custom parameters.
   * @param fpmmImplementation The address of the FPMM implementation
   * @param customOracleAdapter The address of the custom oracle adapter contract
   * @param customProxyAdmin The address of the custom proxy admin contract
   * @param customOwner The address of the custom owner
   * @param token0 The address of the first token
   * @param token1 The address of the second token
   * @param referenceRateFeedID The address of the reference rate feed
   * @param invertRateFeed Wether to invert the rate feed so that the base is asset0 and quote is asset1
   * @param customParams The custom parameters for the deployed FPMM
   * @return proxy The address of the deployed FPMM proxy
   */
  function deployFPMM(
    address fpmmImplementation,
    address customOracleAdapter,
    address customProxyAdmin,
    address customOwner,
    address token0,
    address token1,
    address referenceRateFeedID,
    bool invertRateFeed,
    IFPMM.FPMMParams memory customParams
  ) external returns (address proxy);
}
