// SPDX-License-Identifier: MIT
pragma solidity >=0.5.17 <0.8.19;
pragma experimental ABIEncoderV2;

interface IBancorExchangeProvider {
  struct PoolExchange {
    address reserveAsset;
    address tokenAddress;
    uint256 tokenSupply;
    uint256 reserveBalance;
    uint32 reserveRatio;
    uint32 exitConribution;
  }

  /* ------- Events ------- */

  /**
   * @notice Emitted when the broker address is updated.
   * @param newBroker The address of the new broker.
   */
  event BrokerUpdated(address indexed newBroker);

  /**
   * @notice Emitted when the reserve contract is set.
   * @param newReserve The address of the new reserve.
   */
  event ReserveUpdated(address indexed newReserve);

  /**
   * @notice Emitted when a new PoolExchange has been created.
   * @param exchangeId The id of the new PoolExchange
   * @param reserveAsset The address of the reserve asset
   * @param tokenAddress The address of the token
   */
  event ExchangeCreated(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  /**
   * @notice Emitted when a PoolExchange has been destroyed.
   * @param exchangeId The id of the PoolExchange
   * @param reserveAsset The address of the reserve asset
   * @param tokenAddress The address of the token
   */
  event ExchangeDestroyed(bytes32 indexed exchangeId, address indexed reserveAsset, address indexed tokenAddress);

  /**
   * @notice Emitted when the exit contribution for a pool is set.
   * @param exchangeId The id of the pool
   * @param exitContribution The exit contribution
   */
  event ExitContributionSet(bytes32 indexed exchangeId, uint256 exitContribution);

  /* ------- Functions ------- */

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
  function setExitContribution(bytes32 exchangeId, uint32 exitContribution) external;

  /**
   * @notice gets the current price based of the bancor formula
   * @param exchangeId The id of the exchange to get the price for
   * @return price the current continious price
   */
  function currentPrice(bytes32 exchangeId) external returns (uint256 price);
}
