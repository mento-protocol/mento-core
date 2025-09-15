// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IAdaptore } from "../interfaces/IAdaptore.sol";
import { IBreakerBox } from "../interfaces/IBreakerBox.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IMarketHoursBreaker } from "../interfaces/IMarketHoursBreaker.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract Adaptore is IAdaptore, OwnableUpgradeable {
  /* ========== CONSTANTS ========== */

  uint256 public constant TRADING_MODE_BIDIRECTIONAL = 0;

  // keccak256(abi.encode(uint256(keccak256("mento.storage.Adaptore")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant _ADAPTORE_STORAGE_LOCATION =
    0xd880fc8796ff7fc4b20c6242198b153ac9d227642be16c844e981c5031096c00;

  /* ========== CONSTRUCTOR ========== */

  /**
   * @notice Contract constructor
   * @param disable Boolean to disable initializers for implementation contract
   */
  constructor(bool disable) {
    if (disable) {
      _disableInitializers();
    }
  }

  /* ========== INITIALIZATION ========== */

  /// @inheritdoc IAdaptore
  function initialize(address _sortedOracles, address _breakerBox, address _marketHoursBreaker) external initializer {
    __Ownable_init();

    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
    setMarketHoursBreaker(_marketHoursBreaker);
  }

  /* ========== VIEW FUNCTIONS ========== */

  function sortedOracles() external view returns (ISortedOracles) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();
    return $.sortedOracles;
  }

  function breakerBox() external view returns (IBreakerBox) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();
    return $.breakerBox;
  }

  function marketHoursBreaker() external view returns (IMarketHoursBreaker) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();
    return $.marketHoursBreaker;
  }

  /* ========== ADMIN FUNCTIONS ========== */

  /// @inheritdoc IAdaptore
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "Adaptore: ZERO_ADDRESS");

    AdaptoreStorage storage $ = _getAdaptoreStorage();
    address oldSortedOracles = address($.sortedOracles);
    $.sortedOracles = ISortedOracles(_sortedOracles);

    emit SortedOraclesUpdated(oldSortedOracles, _sortedOracles);
  }

  /// @inheritdoc IAdaptore
  function setBreakerBox(address _breakerBox) public onlyOwner {
    require(_breakerBox != address(0), "Adaptore: ZERO_ADDRESS");

    AdaptoreStorage storage $ = _getAdaptoreStorage();
    address oldBreakerBox = address($.breakerBox);
    $.breakerBox = IBreakerBox(_breakerBox);

    emit BreakerBoxUpdated(oldBreakerBox, _breakerBox);
  }

  /// @inheritdoc IAdaptore
  function setMarketHoursBreaker(address _marketHoursBreaker) public onlyOwner {
    require(_marketHoursBreaker != address(0), "Adaptore: ZERO_ADDRESS");

    AdaptoreStorage storage $ = _getAdaptoreStorage();
    address oldMarketHoursBreaker = address($.marketHoursBreaker);
    $.marketHoursBreaker = IMarketHoursBreaker(_marketHoursBreaker);

    emit MarketHoursBreakerUpdated(oldMarketHoursBreaker, _marketHoursBreaker);
  }

  /* ========== EXTERNAL FUNCTIONS ========== */

  /// @inheritdoc IAdaptore
  function isMarketOpen() external view returns (bool) {
    return _isMarketOpen();
  }

  /// @inheritdoc IAdaptore
  function getTradingMode(address rateFeedID) external view returns (uint8) {
    return _getTradingMode(rateFeedID);
  }

  /// @inheritdoc IAdaptore
  function getRate(address rateFeedID) external view returns (RateInfo memory) {
    RateInfo memory rateInfo;

    (uint256 numerator, uint256 denominator) = _getOracleRate(rateFeedID);

    rateInfo.numerator = numerator;
    rateInfo.denominator = denominator;
    rateInfo.tradingMode = _getTradingMode(rateFeedID);
    rateInfo.isRecent = _hasRecentRate(rateFeedID);
    rateInfo.isMarketOpen = _isMarketOpen();

    return rateInfo;
  }

  function getRateIfValid(address rateFeedID) external view returns (uint256 numerator, uint256 denominator) {
    require(_isMarketOpen(), "Adaptore: MARKET_CLOSED");
    require(_getTradingMode(rateFeedID) == TRADING_MODE_BIDIRECTIONAL, "Adaptore: TRADING_SUSPENDED");
    require(_hasRecentRate(rateFeedID), "Adaptore: NO_RECENT_RATE");

    return _getOracleRate(rateFeedID);
  }

  /// @inheritdoc IAdaptore
  function hasRecentRate(address rateFeedID) external view returns (bool) {
    return _hasRecentRate(rateFeedID);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  function _isMarketOpen() private view returns (bool) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    return $.marketHoursBreaker.isMarketOpen(block.timestamp);
  }

  function _getTradingMode(address rateFeedID) private view returns (uint8) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    return $.breakerBox.getRateFeedTradingMode(rateFeedID);
  }

  function _getOracleRate(address rateFeedID) private view returns (uint256 numerator, uint256 denominator) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    (numerator, denominator) = $.sortedOracles.medianRate(rateFeedID);

    numerator = numerator / 1e6;
    denominator = denominator / 1e6;
  }

  function _hasRecentRate(address rateFeedID) private view returns (bool) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    uint256 reportExpiry = $.sortedOracles.getTokenReportExpirySeconds(rateFeedID);
    uint256 reportTs = $.sortedOracles.medianTimestamp(rateFeedID);

    return reportTs > block.timestamp - reportExpiry;
  }

  /**
   * @notice Returns the pointer to the AdaptoreStorage struct.
   * @return $ The pointer to the AdaptoreStorage struct
   */
  function _getAdaptoreStorage() private pure returns (AdaptoreStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := _ADAPTORE_STORAGE_LOCATION
    }
  }
}
