// SPDX-License-Identifier: MIT
import "../../interfaces/IExchangeProvider.sol";

pragma solidity >=0.8.18;

interface IBancorExchangeProvider is IExchangeProvider {
  struct BancorExchange {
    address reserveAsset;
    address tokenAddress;
    uint256 tokenSupply;
    uint256 reserveBalance;
    uint32 reserveRatio;
    uint32 exitContribution;
  }

  /**
   * @notice Retrieves the pool with the specified exchangeId.
   * @param exchangeId The id of the pool to be retrieved.
   * @return exchange The PoolExchange with that ID.
   */
  function getBancorExchange(bytes32 exchangeId) external view returns (BancorExchange memory exchange);

  /**
   * @notice Get all exchange IDs.
   * @return exchangeIds List of the exchangeIds.
   */
  function getExchangeIds() external view returns (bytes32[] memory exchangeIds);

  /**
   * @notice Create a PoolExchange with the provided data.
   * @param exchange The PoolExchange to be created.
   * @return exchangeId The id of the exchange.
   */
  function createExchange(BancorExchange calldata exchange) external returns (bytes32 exchangeId);

  /**
   * @notice Delete a PoolExchange.
   * @param exchangeId The PoolExchange to be created.
   * @param exchangeIdIndex The index of the exchangeId in the exchangeIds array.
   * @return destroyed - true on successful delition.
   */
  function destroyExchange(bytes32 exchangeId, uint256 exchangeIdIndex) external returns (bool destroyed);

  /**
   * @notice Set the exit contribution for a given exchange
   * @param exchangeId The id of the exchange
   * @param exitContribution The exit contribution to be set
   */
  function setExitContribution(bytes32 exchangeId, uint32 exitContribution) external;

  function getAmountOut(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountIn
  ) external view returns (uint256);

  function getAmountIn(
    bytes32 exchangeId,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external view returns (uint256);

  function swapOut(bytes32 exchangeId, address tokenIn, address tokenOut, uint256 amountOut) external returns (uint256);

  function swapIn(bytes32 exchangeId, address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256);

  /**
   * @notice gets the current price based of the bancor formula
   * @param exchangeId The id of the exchange to get the price for
   * @return the current price
   */
  function currentPrice(bytes32 exchangeId) external returns (uint256);
}
