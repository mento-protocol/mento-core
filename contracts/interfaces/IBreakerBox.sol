pragma solidity ^0.5.13;

/**
 * @title Breaker Box Interface
 * @notice Defines the basic interface for the Breaker Box
 */
interface IBreakerBox {
  /**
   * @dev Used to track additional info about
   *      the current trading mode an exchange is in.
   *      LastUpdatedTime helps to check cooldown.
   *      LastUpdatedBlock helps to determine if check should be executed.
   */
  struct TradingModeInfo {
    uint64 tradingMode;
    uint64 lastUpdatedTime;
    uint128 lastUpdatedBlock;
  }

  /**
   * @notice Emitted when a new breaker is added to the breaker box.
   * @param breaker The address of the new breaker.
   */
  event BreakerAdded(address indexed breaker);

  /**
   * @notice Emitted when a breaker is removed from the breaker box.
   * @param breaker The address of the breaker that was removed.
   */
  event BreakerRemoved(address indexed breaker);

  /**
   * @notice Emitted when a breaker is tripped by an exchange.
   * @param breaker The address of the breaker that was tripped.
   * @param exchange The address of the exchange.
   */
  event BreakerTripped(address indexed breaker, address indexed exchange);

  /**
   * @notice Emitted when a new referenceRate is added to the breaker box.
   * @param referenceRateID The address of the referenceRate that was added.
   */
  event ReferenceRateIDAdded(address indexed referenceRateID);

  /**
   * @notice Emitted when a referenceRate is removed from the breaker box.
   * @param referenceRateID The referenceRate of the exchange that was removed.
   */
  event ReferenceRateIDRemoved(address indexed referenceRateID);

  /**
   * @notice Emitted when the trading mode for an exchange is updated
   * @param exchange The address of the exchange.
   * @param tradingMode The new trading mode of the exchange.
   */
  event TradingModeUpdated(address indexed exchange, uint256 tradingMode);

  /**
   * @notice Emitted after a reset attempt is successful.
   * @param exchange The address of the exchange.
   * @param breaker The address of the breaker.
   */
  event ResetSuccessful(address indexed exchange, address indexed breaker);

  /**
   * @notice  Emitted after a reset attempt fails when the
   *          exchange fails the breakers reset criteria.
   * @param exchange The address of the exchange.
   * @param breaker The address of the breaker.
   */
  event ResetAttemptCriteriaFail(address indexed exchange, address indexed breaker);

  /**
   * @notice Emitted after a reset attempt fails when cooldown time has not elapsed.
   * @param exchange The address of the exchange.
   * @param breaker The address of the breaker.
   */
  event ResetAttemptNotCool(address indexed exchange, address indexed breaker);

  /**
   * @notice Emitted when the sortedOracles address is updated.
   * @param newSortedOracles The address of the new sortedOracles.
   */
  event SortedOraclesUpdated(address indexed newSortedOracles);

  /**
   * @notice Retrives an ordered array of all breaker addresses.
   */
  function getBreakers() external view returns (address[] memory);

  /**
   * @notice Checks if a breaker with the specified address has been added to the breaker box.
   * @param breaker The address of the breaker to check;
   * @return A bool indicating whether or not the breaker has been added.
   */
  function isBreaker(address breaker) external view returns (bool);

  /**
   * @notice Checks breakers for the exchange with the specified id 
             and sets correct trading mode if any breakers are tripped
             or need to be reset.
   * @param  referenceRate The registryId of the exchange to run checks for.
   */
  function checkAndSetBreakers(address referenceRate) external;

  /**
   * @notice Gets the trading mode for the specified exchange.
   * @param  exchange The address of the exchange to retrieve the trading mode for.
   */
  function getTradingMode(address exchange) external view returns (uint256 tradingMode);
}
