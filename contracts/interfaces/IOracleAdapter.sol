// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { IBreakerBox } from "./IBreakerBox.sol";
import { ISortedOracles } from "./ISortedOracles.sol";
import { IMarketHoursBreaker } from "./IMarketHoursBreaker.sol";
import { AggregatorV3Interface } from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

interface IOracleAdapter {
  /* ============================================================ */
  /* ======================== Structs =========================== */
  /* ============================================================ */

  /// @notice Struct to store OracleAdapter contract state
  /// @custom:storage-location erc7201:mento.storage.OracleAdapter
  struct OracleAdapterStorage {
    // Contract for querying oracle price feeds
    ISortedOracles sortedOracles;
    // Contract for checking trading modes
    IBreakerBox breakerBox;
    // Contract for checking market hours
    IMarketHoursBreaker marketHoursBreaker;
    // Contract for checking L2 sequencer status
    AggregatorV3Interface l2SequencerUptimeFeed;
    // Grace period for the L2 sequencer
    uint256 l2SequencerGracePeriod;
  }

  /// @notice Struct to store info about a rate
  struct RateInfo {
    uint256 numerator;
    uint256 denominator;
    uint8 tradingMode;
    bool isRecent;
    bool isFXMarketOpen;
  }

  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  // @notice Thrown when the FX market is closed
  error FXMarketClosed();
  // @notice Thrown when trading is suspended because of a breaker
  error TradingSuspended();
  // @notice Thrown when the rate in sorted oracles is 0
  error InvalidRate();
  // @notice Thrown when no recent rate is available
  error NoRecentRate();
  // @notice Thrown when trying to set a zero address as a contract address
  error ZeroAddress();
  // @notice Thrown when the L2 sequencer grace period is invalid
  error InvalidL2SequencerGracePeriod();

  /* ============================================================ */
  /* ======================== Events ============================ */
  /* ============================================================ */

  /**
   * @notice Emitted when the SortedOracles contract is updated
   * @param oldSortedOracles Previous SortedOracles address
   * @param newSortedOracles New SortedOracles address
   */
  event SortedOraclesUpdated(address indexed oldSortedOracles, address indexed newSortedOracles);

  /**
   * @notice Emitted when the BreakerBox contract is updated
   * @param oldBreakerBox Previous BreakerBox address
   * @param newBreakerBox New BreakerBox address
   */
  event BreakerBoxUpdated(address indexed oldBreakerBox, address indexed newBreakerBox);

  /**
   * @notice Emitted when the MarketHoursBreaker contract is updated
   * @param oldMarketHoursBreaker Previous MarketHoursBreaker address
   * @param newMarketHoursBreaker New MarketHoursBreaker address
   */
  event MarketHoursBreakerUpdated(address indexed oldMarketHoursBreaker, address indexed newMarketHoursBreaker);

  /**
   * @notice Emitted when the L2 sequencer uptime feed contract is updated
   * @param oldL2SequencerUptimeFeed Previous L2SequencerUptimeFeed address
   * @param newL2SequencerUptimeFeed New L2SequencerUptimeFeed address
   */
  event L2SequencerUptimeFeedUpdated(
    address indexed oldL2SequencerUptimeFeed,
    address indexed newL2SequencerUptimeFeed
  );

  /**
   * @notice Emitted when the L2 sequencer grace period is updated
   * @param oldSequencerGracePeriod Previous grace period for the L2 sequencer
   * @param newSequencerGracePeriod New grace period for the L2 sequencer
   */
  event L2SequencerGracePeriodUpdated(uint256 indexed oldSequencerGracePeriod, uint256 indexed newSequencerGracePeriod);

  /* ============================================================ */
  /* ====================== View Functions ====================== */
  /* ============================================================ */

  /**
   * @notice Returns the contract for oracle price feeds
   * @return Address of the SortedOracles contract
   */
  function sortedOracles() external view returns (ISortedOracles);

  /**
   * @notice Returns the contract for checking trading modes
   * @return Address of the BreakerBox contract
   */
  function breakerBox() external view returns (IBreakerBox);

  /**
   * @notice Returns the contract for checking market hours
   * @return Address of the MarketHoursBreaker contract
   */
  function marketHoursBreaker() external view returns (IMarketHoursBreaker);

  /**
   * @notice Returns the contract for checking the L2 sequencer status
   * @return Address of the L2SequencerUptimeFeed contract
   */
  function l2SequencerUptimeFeed() external view returns (AggregatorV3Interface);

  /**
   * @notice Returns the grace period for the L2 sequencer
   * @return uint256 Grace period for the L2 sequencer
   */
  function l2SequencerGracePeriod() external view returns (uint256);

  /**
   * @notice Returns true if the market is open based on FX market hours
   * @return true if the market is open, false otherwise
   */
  function isFXMarketOpen() external view returns (bool);

  /**
   * @notice Returns true if the rate for a given rate feed ID is recent
   * @param rateFeedID The address of the rate feed
   * @return true if the rate is recent, false otherwise
   */
  function hasRecentRate(address rateFeedID) external view returns (bool);

  /**
   * @notice Returns the exchange rate for a given rate feed ID
   * with 18 decimals of precision, along with other info
   * @param rateFeedID The address of the rate feed
   * @return rateInfo The rate info
   */
  function getRate(address rateFeedID) external view returns (RateInfo memory);

  /**
   * @notice Returns the exchange rate for a given rate feed ID
   * with 18 decimals of precision if considered valid, based on
   * trading mode, and recent rate, otherwise reverts
   * @param rateFeedID The address of the rate feed
   * @return numerator The numerator of the rate
   * @return denominator The denominator of the rate
   */
  function getRateIfValid(address rateFeedID) external view returns (uint256 numerator, uint256 denominator);

  /**
   * @notice Returns the exchange rate for a given rate feed ID
   * with 18 decimals of precision if considered valid, based on
   * FX market hours, trading mode, and recent rate, otherwise reverts
   * @param rateFeedID The address of the rate feed
   * @return numerator The numerator of the rate
   * @return denominator The denominator of the rate
   */
  function getFXRateIfValid(address rateFeedID) external view returns (uint256 numerator, uint256 denominator);

  /**
   * @notice Returns the trading mode for a given rate feed ID
   * @param rateFeedID The address of the rate feed
   * @return The trading mode
   */
  function getTradingMode(address rateFeedID) external view returns (uint8);

  /**
   * @notice Ensures that the rate feed is valid by checking trading mode and rate freshness
   * @dev Reverts if trading is suspended or rate is not recent
   * @param rateFeedID The address of the rate feed
   */
  function ensureRateValid(address rateFeedID) external view;

  /**
   * @notice Ensures that the L2 sequencer is up and the grace period has passed
   * @dev Reverts if the L2 sequencer is not up or the grace period has not passed
   */
  function ensureL2SequencerUp() external view returns (bool);

  /* ============================================================ */
  /* ==================== Mutative Functions ==================== */
  /* ============================================================ */

  /**
   * @notice Initializes the OracleAdapter contract
   * @param _sortedOracles The address of the sorted oracles contract
   * @param _breakerBox The address of the breaker box contract
   * @param _marketHoursBreaker The address of the market hours breaker contract
   * @param _initialOwner The address to transfer ownership to
   */
  function initialize(
    address _sortedOracles,
    address _breakerBox,
    address _marketHoursBreaker,
    address _l2SequencerUptimeFeed,
    uint256 _sequencerGracePeriod,
    address _initialOwner
  ) external;

  /**
   * @notice Sets the address of the sorted oracles contract
   * @param _sortedOracles The address of the sorted oracles contract
   */
  function setSortedOracles(address _sortedOracles) external;

  /**
   * @notice Sets the address of the breaker box contract
   * @param _breakerBox The address of the breaker box contract
   */
  function setBreakerBox(address _breakerBox) external;

  /**
   * @notice Sets the address of the market hours breaker contract
   * @param _marketHoursBreaker The address of the market hours breaker contract
   */
  function setMarketHoursBreaker(address _marketHoursBreaker) external;

  /**
   * @notice Sets the address of the L2 sequencer uptime feed contract
   * @param _l2SequencerUptimeFeed The address of the L2 sequencer uptime feed contract
   */
  function setL2SequencerUptimeFeed(address _l2SequencerUptimeFeed) external;
}
