// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.13 <0.8.19;
pragma experimental ABIEncoderV2;

/*
 * @title Broker Interface for trader functions
 * @notice The broker is responsible for executing swaps and keeping track of trading limits.
 */
interface IBroker {
  /**
   * @dev The State struct contains the current state of a trading limit config.
   * @param lastUpdated0 The timestamp of the last reset of netflow0.
   * @param lastUpdated1 The timestamp of the last reset of netflow1.
   * @param netflow0 The current netflow of the asset for limit0.
   * @param netflow1 The current netflow of the asset for limit1.
   * @param netflowGlobal The current netflow of the asset for limitGlobal.
   */
  struct State {
    uint32 lastUpdated0;
    uint32 lastUpdated1;
    int48 netflow0;
    int48 netflow1;
    int48 netflowGlobal;
  }

  /**
   * @dev The Config struct contains the configuration of trading limits.
   * @param timestep0 The time window in seconds for limit0.
   * @param timestep1 The time window in seconds for limit1.
   * @param limit0 The limit0 for the asset.
   * @param limit1 The limit1 for the asset.
   * @param limitGlobal The global limit for the asset.
   * @param flags A bitfield of flags to enable/disable the individual limits.
   */
  struct Config {
    uint32 timestep0;
    uint32 timestep1;
    int48 limit0;
    int48 limit1;
    int48 limitGlobal;
    uint8 flags;
  }

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
  event TradingLimitConfigured(bytes32 exchangeId, address token, Config config);

  function isExchangeProvider(address exchangeProvider) external view returns (bool);

  function exchangeReserve(address exchangeProvider) external view returns (address);

  function configureTradingLimit(
    bytes32 exchangeId,
    address token,
    Config calldata config
  ) external;

  /**
   * @notice Initialize the broker with the exchange providers and reserves.
   * @param _exchangeProviders The addresses of the exchange providers.
   * @param _reserves The addresses of the reserves.
   */
  function initialize(address[] calldata _exchangeProviders, address[] calldata _reserves) external;

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
