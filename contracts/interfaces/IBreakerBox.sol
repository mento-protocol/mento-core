pragma solidity ^0.5.13;

/**
 * @title Breaker Box Interface
 * @notice Defines the basic interface for the Breaker Box
 */
interface IBreakerBox {
  /**
   * @dev Used to track additional info about
   *      the current trading mode a specific rate feed ID is in.
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
   * @notice Emitted when a breaker is tripped by a rateFeedID.
   * @param breaker The address of the breaker that was tripped.
   * @param rateFeedID The address of the rateFeedID.
   */
  event BreakerTripped(address indexed breaker, address indexed rateFeedID);

  /**
   * @notice Emitted when a new rateFeedID is added to the breaker box.
   * @param rateFeedID The address of the rateFeedID that was added.
   */
  event RateFeedAdded(address indexed rateFeedID);

  /**
   * @notice Emitted when a rateFeedID is removed from the breaker box.
   * @param rateFeedID The rateFeedID that was removed.
   */
  event RateFeedRemoved(address indexed rateFeedID);

  /**
   * @notice Emitted when the trading mode for a rateFeedID is updated
   * @param rateFeedID The address of the rateFeedID.
   * @param tradingMode The new trading mode of the rateFeedID.
   */
  event TradingModeUpdated(address indexed rateFeedID, uint256 tradingMode);

  /**
   * @notice Emitted after a reset attempt is successful.
   * @param rateFeedID The address of the rateFeedID.
   * @param breaker The address of the breaker.
   */
  event ResetSuccessful(address indexed rateFeedID, address indexed breaker);

  /**
   * @notice  Emitted after a reset attempt fails when the
   *          rateFeedID fails the breakers reset criteria.
   * @param rateFeedID The address of the rateFeedID.
   * @param breaker The address of the breaker.
   */
  event ResetAttemptCriteriaFail(address indexed rateFeedID, address indexed breaker);

  /**
   * @notice Emitted after a reset attempt fails when cooldown time has not elapsed.
   * @param rateFeedID The address of the rateFeedID.
   * @param breaker The address of the breaker.
   */
  event ResetAttemptNotCool(address indexed rateFeedID, address indexed breaker);

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
   * @notice Checks breakers for the rateFeedID and sets correct trading mode
   * if any breakers are tripped or need to be reset.
   * @param rateFeedID The registryId of the rateFeedID to run checks for.
   */
  function checkAndSetBreakers(address rateFeedID) external;

  /**
   * @notice Gets the trading mode for the specified rateFeedID.
   * @param rateFeedID The address of the rateFeedID to retrieve the trading mode for.
   */
  function getRateFeedTradingMode(address rateFeedID) external view returns (uint256 tradingMode);
}
