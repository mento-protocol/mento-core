// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IOracleAdapter } from "../interfaces/IOracleAdapter.sol";
import { IBreakerBox } from "../interfaces/IBreakerBox.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IMarketHoursBreaker } from "../interfaces/IMarketHoursBreaker.sol";
import { AggregatorV3Interface } from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract OracleAdapter is IOracleAdapter, OwnableUpgradeable {
  /* ============================================================ */
  /* ======================== Constants ========================= */
  /* ============================================================ */

  uint256 public constant TRADING_MODE_BIDIRECTIONAL = 0;

  // keccak256(abi.encode(uint256(keccak256("mento.storage.OracleAdapter")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant _ORACLE_ADAPTER_STORAGE_LOCATION =
    0x04e664c42d77958a8a4a4091eaa097623a29a223ec89dc71155113e263f9c400;

  /* ============================================================ */
  /* ======================== Constructor ======================= */
  /* ============================================================ */

  /**
   * @notice Contract constructor
   * @param disable Boolean to disable initializers for implementation contract
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /* ============================================================ */
  /* ==================== Initialization ======================== */
  /* ============================================================ */

  /// @inheritdoc IOracleAdapter
  function initialize(
    address _sortedOracles,
    address _breakerBox,
    address _marketHoursBreaker,
    address _l2SequencerUptimeFeed,
    address _initialOwner
  ) external initializer {
    __Ownable_init();

    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
    setMarketHoursBreaker(_marketHoursBreaker);
    setL2SequencerUptimeFeed(_l2SequencerUptimeFeed);

    transferOwnership(_initialOwner);
  }

  /* ============================================================ */
  /* ==================== Admin Functions ======================= */
  /* ============================================================ */

  /// @inheritdoc IOracleAdapter
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    if (_sortedOracles == address(0)) revert ZeroAddress();

    OracleAdapterStorage storage $ = _getStorage();
    address oldSortedOracles = address($.sortedOracles);
    $.sortedOracles = ISortedOracles(_sortedOracles);

    emit SortedOraclesUpdated(oldSortedOracles, _sortedOracles);
  }

  /// @inheritdoc IOracleAdapter
  function setBreakerBox(address _breakerBox) public onlyOwner {
    if (_breakerBox == address(0)) revert ZeroAddress();

    OracleAdapterStorage storage $ = _getStorage();
    address oldBreakerBox = address($.breakerBox);
    $.breakerBox = IBreakerBox(_breakerBox);

    emit BreakerBoxUpdated(oldBreakerBox, _breakerBox);
  }

  /// @inheritdoc IOracleAdapter
  function setMarketHoursBreaker(address _marketHoursBreaker) public onlyOwner {
    if (_marketHoursBreaker == address(0)) revert ZeroAddress();

    OracleAdapterStorage storage $ = _getStorage();
    address oldMarketHoursBreaker = address($.marketHoursBreaker);
    $.marketHoursBreaker = IMarketHoursBreaker(_marketHoursBreaker);

    emit MarketHoursBreakerUpdated(oldMarketHoursBreaker, _marketHoursBreaker);
  }

  /// @inheritdoc IOracleAdapter
  function setL2SequencerUptimeFeed(address _l2SequencerUptimeFeed) public onlyOwner {
    OracleAdapterStorage storage $ = _getStorage();

    address oldL2SequencerUptimeFeed = address($.l2SequencerUptimeFeed);
    $.l2SequencerUptimeFeed = AggregatorV3Interface(_l2SequencerUptimeFeed);

    emit L2SequencerUptimeFeedUpdated(oldL2SequencerUptimeFeed, _l2SequencerUptimeFeed);
  }

  /* ============================================================ */
  /* ===================== View Functions ======================= */
  /* ============================================================ */

  function sortedOracles() external view returns (ISortedOracles) {
    OracleAdapterStorage storage $ = _getStorage();
    return $.sortedOracles;
  }

  function breakerBox() external view returns (IBreakerBox) {
    OracleAdapterStorage storage $ = _getStorage();
    return $.breakerBox;
  }

  function marketHoursBreaker() external view returns (IMarketHoursBreaker) {
    OracleAdapterStorage storage $ = _getStorage();
    return $.marketHoursBreaker;
  }

  function l2SequencerUptimeFeed() external view returns (AggregatorV3Interface) {
    OracleAdapterStorage storage $ = _getStorage();
    return $.l2SequencerUptimeFeed;
  }

  /// @inheritdoc IOracleAdapter
  function isFXMarketOpen() external view returns (bool) {
    return _isFXMarketOpen();
  }

  /// @inheritdoc IOracleAdapter
  function getTradingMode(address rateFeedID) external view returns (uint8) {
    return _getTradingMode(rateFeedID);
  }

  /// @inheritdoc IOracleAdapter
  function getRate(address rateFeedID) external view returns (RateInfo memory) {
    // slither-disable-next-line uninitialized-local
    RateInfo memory rateInfo;

    (uint256 numerator, uint256 denominator) = _getOracleRate(rateFeedID);

    rateInfo.numerator = numerator;
    rateInfo.denominator = denominator;
    rateInfo.tradingMode = _getTradingMode(rateFeedID);
    rateInfo.isRecent = _hasRecentRate(rateFeedID);
    rateInfo.isFXMarketOpen = _isFXMarketOpen();

    return rateInfo;
  }

  /// @inheritdoc IOracleAdapter
  function getRateIfValid(address rateFeedID) external view returns (uint256 numerator, uint256 denominator) {
    if (_getTradingMode(rateFeedID) != TRADING_MODE_BIDIRECTIONAL) revert TradingSuspended();
    if (!_hasRecentRate(rateFeedID)) revert NoRecentRate();

    return _getOracleRate(rateFeedID);
  }

  /// @inheritdoc IOracleAdapter
  function getFXRateIfValid(address rateFeedID) external view returns (uint256 numerator, uint256 denominator) {
    if (!_isFXMarketOpen()) revert FXMarketClosed();
    if (_getTradingMode(rateFeedID) != TRADING_MODE_BIDIRECTIONAL) revert TradingSuspended();
    if (!_hasRecentRate(rateFeedID)) revert NoRecentRate();

    return _getOracleRate(rateFeedID);
  }

  /// @inheritdoc IOracleAdapter
  function hasRecentRate(address rateFeedID) external view returns (bool) {
    return _hasRecentRate(rateFeedID);
  }

  /// @inheritdoc IOracleAdapter
  function ensureRateValid(address rateFeedID) external view {
    if (_getTradingMode(rateFeedID) != TRADING_MODE_BIDIRECTIONAL) revert TradingSuspended();
    if (!_hasRecentRate(rateFeedID)) revert NoRecentRate();
    _getOracleRate(rateFeedID);
  }

  /// @inheritdoc IOracleAdapter
  function isL2SequencerUp(uint256 gracePeriod) external view returns (bool) {
    OracleAdapterStorage storage $ = _getStorage();

    if (address($.l2SequencerUptimeFeed) == address(0)) return true;

    (, int256 answer, , uint256 upSince, ) = $.l2SequencerUptimeFeed.latestRoundData();
    return answer == 0 && block.timestamp - upSince > gracePeriod;
  }

  /* ============================================================ */
  /* ==================== Private Functions ===================== */
  /* ============================================================ */

  function _isFXMarketOpen() private view returns (bool) {
    OracleAdapterStorage storage $ = _getStorage();

    return $.marketHoursBreaker.isFXMarketOpen(block.timestamp);
  }

  function _getTradingMode(address rateFeedID) private view returns (uint8) {
    OracleAdapterStorage storage $ = _getStorage();

    return $.breakerBox.getRateFeedTradingMode(rateFeedID);
  }

  function _getOracleRate(address rateFeedID) private view returns (uint256 numerator, uint256 denominator) {
    OracleAdapterStorage storage $ = _getStorage();

    (numerator, denominator) = $.sortedOracles.medianRate(rateFeedID);
    if (numerator == 0 || denominator == 0) revert InvalidRate();

    numerator = numerator / 1e6;
    denominator = denominator / 1e6;
  }

  function _hasRecentRate(address rateFeedID) private view returns (bool) {
    OracleAdapterStorage storage $ = _getStorage();

    uint256 reportExpiry = $.sortedOracles.getTokenReportExpirySeconds(rateFeedID);
    uint256 reportTs = $.sortedOracles.medianTimestamp(rateFeedID);

    return reportTs > block.timestamp - reportExpiry;
  }

  /**
   * @notice Returns the pointer to the OracleAdapterStorage struct.
   * @return $ The pointer to the OracleAdapterStorage struct
   */
  function _getStorage() private pure returns (OracleAdapterStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := _ORACLE_ADAPTER_STORAGE_LOCATION
    }
  }
}
