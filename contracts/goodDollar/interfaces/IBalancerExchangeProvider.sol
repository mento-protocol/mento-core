// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IBalancerExchangeProvider {
  struct PoolExchange {
    address reserveAsset;
    address tokenAddress;
    uint256 tokenSupply;
    uint256 reserveBalance;
    uint256 reserveRatio;
    uint256 exitConribution;
  }

  /**
   * @notice Retrieves the pool with the specified exchangeId.
   * @param exchangeId The id of the pool to be retrieved.
   * @return exchange The PoolExchange with that ID.
   */
  function getPoolExchange(bytes32 exchangeId) external view returns (PoolExchange memory exchange);

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
  function createExchange(PoolExchange calldata exchange) external returns (bytes32 exchangeId);

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
  function setExitContribution(bytes32 exchangeId, uint256 exitContribution) external;

  /**
   * @notice gets the current price based of the bancor formula
   * @param exchangeId The id of the exchange to get the price for
   * @return the current price
   */
  function currentPrice(bytes32 exchangeId) external returns (uint256);
}
