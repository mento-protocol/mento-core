// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.5.13 <0.9;
pragma experimental ABIEncoderV2;

import { ITradingLimits } from "./ITradingLimits.sol";

/*
 * @title Broker Interface for trader functions
 * @notice The broker is responsible for executing swaps and keeping track of trading limits.
 */
interface IBroker {
  /**
   * @notice Emitted when a swap occurs.
   * @param exchangeProvider The exchange provider used.
   * @param exchangeId The id of the exchange used.
   * @param trader The user that initiated the swap.
   * @param tokenIn The address of the token that was sold.
   * @param tokenOut The address of the token that was bought.
   * @param amountIn The amount of token sold.
   * @param amountOut The amount of token bought.
   */
  event Swap(
    address exchangeProvider,
    bytes32 indexed exchangeId,
    address indexed trader,
    address indexed tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut
  );

  /**
   * @notice Emitted when a new trading limit is configured.
   * @param exchangeId the exchangeId to target.
   * @param token the token to target.
   * @param config the new trading limits config.
   */
  event TradingLimitConfigured(bytes32 exchangeId, address token, ITradingLimits.Config config);

  /**
   * @notice Execute a token swap with fixed amountIn.
   * @param exchangeProvider the address of the exchange provider for the pair.
   * @param exchangeId The id of the exchange to use.
   * @param tokenIn The token to be sold.
   * @param tokenOut The token to be bought.
   * @param amountIn The amount of tokenIn to be sold.
   * @param amountOutMin Minimum amountOut to be received - controls slippage.
   * @return amountOut The amount of tokenOut to be bought.
   */
  function swapIn(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin
  ) external returns (uint256 amountOut);

  /**
   * @notice Execute a token swap with fixed amountOut.
   * @param exchangeProvider the address of the exchange provider for the pair.
   * @param exchangeId The id of the exchange to use.
   * @param tokenIn The token to be sold.
   * @param tokenOut The token to be bought.
   * @param amountOut The amount of tokenOut to be bought.
   * @param amountInMax Maximum amount of tokenIn that can be traded.
   * @return amountIn The amount of tokenIn to be sold.
   */
  function swapOut(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut,
    uint256 amountInMax
  ) external returns (uint256 amountIn);

  /**
   * @notice Calculate amountOut of tokenOut received for a given amountIn of tokenIn.
   * @param exchangeProvider the address of the exchange provider for the pair.
   * @param exchangeId The id of the exchange to use.
   * @param tokenIn The token to be sold.
   * @param tokenOut The token to be bought.
   * @param amountIn The amount of tokenIn to be sold.
   * @return amountOut The amount of tokenOut to be bought.
   */
  function getAmountOut(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256 amountOut);

  /**
   * @notice Calculate amountIn of tokenIn needed for a given amountOut of tokenOut.
   * @param exchangeProvider the address of the exchange provider for the pair.
   * @param exchangeId The id of the exchange to use.
   * @param tokenIn The token to be sold.
   * @param tokenOut The token to be bought.
   * @param amountOut The amount of tokenOut to be bought.
   * @return amountIn The amount of tokenIn to be sold.
   */
  function getAmountIn(
    address exchangeProvider,
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external view returns (uint256 amountIn);

  /**
   * @notice Get the list of registered exchange providers.
   * @dev This can be used by UI or clients to discover all pairs.
   * @return exchangeProviders the addresses of all exchange providers.
   */
  function getExchangeProviders() external view returns (address[] memory);

  function burnStableTokens(address token, uint256 amount) external returns (bool);

  /**
   * @notice Allows the contract to be upgradable via the proxy.
   * @param _exchangeProviders The addresses of the ExchangeProvider contracts.
   * @param _reserve The address of the Reserve contract.
   */
  function initialize(address[] calldata _exchangeProviders, address _reserve) external;

  /// @notice IOwnable:
  function transferOwnership(address newOwner) external;

  function renounceOwnership() external;

  function owner() external view returns (address);

  /// @notice Getters:
  function reserve() external view returns (address);

  function isExchangeProvider(address exchangeProvider) external view returns (bool);

  /// @notice Setters:
  function addExchangeProvider(address exchangeProvider) external returns (uint256 index);

  function removeExchangeProvider(address exchangeProvider, uint256 index) external;

  function setReserve(address _reserve) external;

  function configureTradingLimit(bytes32 exchangeId, address token, ITradingLimits.Config calldata config) external;

  function tradingLimitsConfig(bytes32 id) external view returns (ITradingLimits.Config memory);

  function tradingLimitsState(bytes32 id) external view returns (ITradingLimits.State memory);

  function exchangeProviders(uint256 i) external view returns (address);
}
