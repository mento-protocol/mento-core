// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { IAdaptore } from "../interfaces/IAdaptore.sol";
import { IBreakerBox } from "../interfaces/IBreakerBox.sol";
import { ISortedOracles } from "../interfaces/ISortedOracles.sol";
import { IMarketHoursBreaker } from "../interfaces/IMarketHoursBreaker.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract Adaptore is IAdaptore, OwnableUpgradeable {
  // TODO: Make Ownable upgradeable/initializable
  // Use storage pointer pattern
  // setters and getters for external contracts

  /* ========== CONSTANTS ========== */

  // keccak256(abi.encode(uint256(keccak256("mento.storage.Adaptore")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant _ADAPTORE_STORAGE_LOCATION =
    0xd880fc8796ff7fc4b20c6242198b153ac9d227642be16c844e981c5031096c00;

  // struct AdaptoreStorage {
  //   ISortedOracles sortedOracles;
  //   IBreakerBox breakerBox;
  //   IMarketHoursBreaker marketHoursBreaker;
  // }

  // ISortedOracles public sortedOracles;
  // IBreakerBox public breakerBox;
  // IMarketHoursBreaker public marketHoursBreaker;

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

  // @inheritdoc IAdaptore
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    require(_sortedOracles != address(0), "Adaptore: ZERO_ADDRESS");

    AdaptoreStorage storage $ = _getAdaptoreStorage();
    address oldSortedOracles = address($.sortedOracles);
    $.sortedOracles = ISortedOracles(_sortedOracles);

    emit SortedOraclesUpdated(oldSortedOracles, _sortedOracles);
  }

  // @inheritdoc IAdaptore
  function setBreakerBox(address _breakerBox) public onlyOwner {
    require(_breakerBox != address(0), "Adaptore: ZERO_ADDRESS");

    AdaptoreStorage storage $ = _getAdaptoreStorage();
    address oldBreakerBox = address($.breakerBox);
    $.breakerBox = IBreakerBox(_breakerBox);

    emit BreakerBoxUpdated(oldBreakerBox, _breakerBox);
  }

  // @inheritdoc IAdaptore
  function setMarketHoursBreaker(address _marketHoursBreaker) public onlyOwner {
    require(_marketHoursBreaker != address(0), "Adaptore: ZERO_ADDRESS");

    AdaptoreStorage storage $ = _getAdaptoreStorage();
    address oldMarketHoursBreaker = address($.marketHoursBreaker);
    $.marketHoursBreaker = IMarketHoursBreaker(_marketHoursBreaker);

    emit MarketHoursBreakerUpdated(oldMarketHoursBreaker, _marketHoursBreaker);
  }

  /* ========== EXTERNAL FUNCTIONS ========== */

  /**
   * @notice Returns true if the market is open
   * @return true if the market is open, false otherwise
   */
  function isMarketOpen() external view returns (bool) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    return $.marketHoursBreaker.isMarketOpen(block.timestamp);
  }

  /**
   * @notice Returns the trading mode for a given rate feed ID
   * @param rateFeedID The address of the rate feed
   * @return The trading mode
   */
  function getTradingMode(address rateFeedID) external view returns (uint8) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    return $.breakerBox.getRateFeedTradingMode(rateFeedID);
  }

  /**
   * @notice Returns the exchange rate for a given rate feed ID
   * with 18 decimals of precision
   * @param rateFeedID The address of the rate feed
   * @return numerator The numerator of the rate
   * @return denominator The denominator of the rate
   */
  function getRate(address rateFeedID) external view returns (uint256 numerator, uint256 denominator) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    (numerator, denominator) = $.sortedOracles.medianRate(rateFeedID);

    numerator = numerator / 1e6;
    denominator = denominator / 1e6;
  }

  /**
   * @notice Returns true if the rate for a given rate feed ID is valid
   * @param rateFeedID The address of the rate feed
   * @return true if the rate is valid, false otherwise
   */
  function hasValidRate(address rateFeedID) external view returns (bool) {
    AdaptoreStorage storage $ = _getAdaptoreStorage();

    uint256 reportExpiry = $.sortedOracles.getTokenReportExpirySeconds(rateFeedID);
    uint256 reportTs = $.sortedOracles.medianTimestamp(rateFeedID);

    return reportTs > block.timestamp - reportExpiry;
  }

  /* ========== INTERNAL FUNCTIONS ========== */

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
