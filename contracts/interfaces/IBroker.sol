// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.8.19;
pragma experimental ABIEncoderV2;

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
   * @notice Initialize the broker with the exchange providers and reserves.
   * @param _exchangeProviders The addresses of the exchange providers.
   * @param _reserves The addresses of the reserves.
   */
  function initialize(address[] calldata _exchangeProviders, address[] calldata _reserves) external;

  /**
   * @notice returns whether an exchange provider is registered.
   * @param exchangeProvider the address of the exchange provider.
   * @return isExchangeProvider true if the exchange provider is registered.
   */
  function isExchangeProvider(address exchangeProvider) external view returns (bool);

  /**
   * @notice returns the reserve address for an exchange provider.
   * @param exchangeProvider the address of the exchange provider.
   * @return reserve the address of the reserve.
   */
  function exchangeReserve(address exchangeProvider) external view returns (address);

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
  function getExchangeProviders() external view returns (address[] memory exchangeProviders);
}
