// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { IBreakerBox } from "./interfaces/IBreakerBox.sol";
import { IBreaker } from "./interfaces/IBreaker.sol";
import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import { AddressLinkedList, LinkedList } from "./common/linkedlists/AddressLinkedList.sol";
import { Initializable } from "./common/Initializable.sol";

/**
 * @title   BreakerBox
 * @notice  The BreakerBox checks the criteria defined in separate breaker contracts
 *          to determine whether or not buying or selling should be allowed for a
 *          specified rateFeedIDs. The contract stores references to all breakers
 *          that hold criteria to be checked, rateFeedIDs that
 *          can make use of the BreakerBox & their current trading.
 */
contract BreakerBox is IBreakerBox, Initializable, Ownable {
  using AddressLinkedList for LinkedList.List;

  /* ==================== State Variables ==================== */

  address[] public rateFeedIDs;
  // Maps rate feed ID to its current trading mode info.
  mapping(address => TradingModeInfo) public rateFeedTradingModes;
  // Maps a trading mode to the associated breaker.
  mapping(uint64 => address) public tradingModeBreaker;
  // Maps a breaker to the associated trading mode.
  mapping(address => uint64) public breakerTradingMode;
  // Ordered list of breakers to be checked.
  LinkedList.List private breakers;

  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  modifier onlyValidBreaker(address breaker, uint64 tradingMode) {
    require(!isBreaker(breaker), "This breaker has already been added");
    require(
      tradingModeBreaker[tradingMode] == address(0),
      "There is already a breaker added with the same trading mode"
    );
    require(tradingMode != 0, "The default trading mode can not have a breaker");
    _;
  }

  /* ==================== Constructor ==================== */

  /**
   * @notice Sets initialized == true on implementation contracts.
   * @param test Set to true to skip implementation initialization.
   */
  constructor(bool test) public Initializable(test) {}

  /**
   * @param _rateFeedIDs rateFeedIDs to be added.
   * @param _sortedOracles The address of the Celo sorted oracles contract.
   */
  function initialize(address[] calldata _rateFeedIDs, ISortedOracles _sortedOracles) external initializer {
    _transferOwnership(msg.sender);
    setSortedOracles(_sortedOracles);
    addRateFeeds(_rateFeedIDs);
  }

  /* ==================== Mutative Functions ==================== */
  /**
   * @notice Sets the address of the sortedOracles contract.
   * @param _sortedOracles The new address of the sorted oracles contract.
   */
  function setSortedOracles(ISortedOracles _sortedOracles) public onlyOwner {
    require(address(_sortedOracles) != address(0), "SortedOracles address must be set");
    sortedOracles = _sortedOracles;
    emit SortedOraclesUpdated(address(_sortedOracles));
  }

  /* ==================== Restricted Functions ==================== */

  /* ---------- Breakers ---------- */

  /**
   * @notice Adds a breaker to the end of the list of breakers & the tradingMode-Breaker mapping.
   * @param breaker The address of the breaker to be added.
   * @param tradingMode The trading mode of the breaker to be added.
   */
  function addBreaker(address breaker, uint64 tradingMode) public onlyOwner onlyValidBreaker(breaker, tradingMode) {
    tradingModeBreaker[tradingMode] = breaker;
    breakerTradingMode[breaker] = tradingMode;
    breakers.push(breaker);
    emit BreakerAdded(breaker);
  }

  /**
   * @notice Adds a breaker to the list of breakers at a specified position.
   * @param breaker The address of the breaker to be added.
   * @param tradingMode The trading mode of the breaker to be added.
   * @param prevBreaker The address of the breaker that should come before the new breaker.
   * @param nextBreaker The address of the breaker that should come after the new breaker.
   */
  function insertBreaker(
    address breaker,
    uint64 tradingMode,
    address prevBreaker,
    address nextBreaker
  ) external onlyOwner onlyValidBreaker(breaker, tradingMode) {
    tradingModeBreaker[tradingMode] = breaker;
    breakerTradingMode[breaker] = tradingMode;
    breakers.insert(breaker, prevBreaker, nextBreaker);
    emit BreakerAdded(breaker);
  }

  // changes trading mode for pairs that have this breaker because if its tripped and if we remove it its stuck
  /**
   * @notice Removes the specified breaker from the list of breakers.
   * @param breaker The address of the breaker to be removed.
   * @dev Will set any rateFeedID using this breakers trading mode to the default trading mode.
   */
  function removeBreaker(address breaker) external onlyOwner {
    require(isBreaker(breaker), "This breaker has not been added");

    uint64 tradingMode = breakerTradingMode[breaker];

    // Set any refenceRateIDs using this breakers trading mode to the default mode.
    address[] memory activeRateFeeds = rateFeedIDs;
    TradingModeInfo memory tradingModeInfo;

    for (uint256 i = 0; i < activeRateFeeds.length; i++) {
      tradingModeInfo = rateFeedTradingModes[activeRateFeeds[i]];
      if (tradingModeInfo.tradingMode == tradingMode) {
        setRateFeedTradingMode(activeRateFeeds[i], 0);
      }
    }

    delete tradingModeBreaker[tradingMode];
    delete breakerTradingMode[breaker];
    breakers.remove(breaker);

    emit BreakerRemoved(breaker);
  }

  /* ---------- rateFeedIDs ---------- */

  /**
   * @notice Adds a rateFeedID to the mapping of monitored rateFeedIDs.
   * @param rateFeedID The address of the rateFeedID to be added.
   */
  function addRateFeed(address rateFeedID) public onlyOwner {
    TradingModeInfo memory info = rateFeedTradingModes[rateFeedID];
    require(info.lastUpdatedTime == 0, "Rate feed ID has already been added");

    require(sortedOracles.getOracles(rateFeedID).length > 0, "Rate feed ID does not exist in oracles list");

    info.tradingMode = 0; // Default trading mode (Bi-directional).
    info.lastUpdatedTime = uint64(block.timestamp);
    info.lastUpdatedBlock = uint128(block.number);
    rateFeedTradingModes[rateFeedID] = info;
    rateFeedIDs.push(rateFeedID);

    emit RateFeedAdded(rateFeedID);
  }

  /**
   * @notice Adds the specified rateFeedIDs to the mapping of monitored rateFeedIDs.
   * @param newRateFeedIDs The array of rateFeedID addresses to be added.
   */
  function addRateFeeds(address[] memory newRateFeedIDs) public onlyOwner {
    for (uint256 i = 0; i < newRateFeedIDs.length; i++) {
      addRateFeed(newRateFeedIDs[i]);
    }
  }

  /**
   * @notice Removes a rateFeedID from the mapping of monitored rateFeedIDs.
   * @param rateFeedID The address of the rateFeedID to be removed.
   */
  function removeRateFeed(address rateFeedID) external onlyOwner {
    uint256 rateFeedIndex;
    for (uint256 i = 0; i < rateFeedIDs.length; i++) {
      if (rateFeedIDs[i] == rateFeedID) {
        rateFeedIndex = i;
        break;
      }
    }

    require(rateFeedIDs[rateFeedIndex] == rateFeedID, "Rate feed ID has not been added");

    uint256 lastIndex = rateFeedIDs.length - 1;
    if (rateFeedIndex != lastIndex) {
      rateFeedIDs[rateFeedIndex] = rateFeedIDs[lastIndex];
    }

    rateFeedIDs.pop();

    delete rateFeedTradingModes[rateFeedID];
    emit RateFeedRemoved(rateFeedID);
  }

  /**
   * @notice Sets the trading mode for the specified rateFeedID.
   * @param rateFeedID The address of the rateFeedID.
   * @param tradingMode The trading mode that should be set.
   */
  function setRateFeedTradingMode(address rateFeedID, uint64 tradingMode) public onlyOwner {
    require(
      tradingMode == 0 || tradingModeBreaker[tradingMode] != address(0),
      "Trading mode must be default or have a breaker set"
    );

    TradingModeInfo memory info = rateFeedTradingModes[rateFeedID];
    require(info.lastUpdatedTime > 0, "Rate feed ID has not been added");

    info.tradingMode = tradingMode;
    info.lastUpdatedTime = uint64(block.timestamp);
    info.lastUpdatedBlock = uint128(block.number);
    rateFeedTradingModes[rateFeedID] = info;

    emit TradingModeUpdated(rateFeedID, tradingMode);
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Returns an array of breaker addresses from start to end.
   * @return An ordered list of breakers.
   */
  function getBreakers() external view returns (address[] memory) {
    return breakers.getKeys();
  }

  /**
   * @notice Checks whether a breaker with the specifed address has been added.
   */
  function isBreaker(address breaker) public view returns (bool) {
    return breakers.contains(breaker);
  }

  /**
   * @notice Returns addresses of rateFeedIDs that have been added.
   */
  function getrateFeeds() external view returns (address[] memory) {
    return rateFeedIDs;
  }

  /**
   * @notice Returns the trading mode for the specified rateFeedID.
   * @param rateFeedID The address of the rateFeedID to retrieve the trading mode for.
   */
  function getRateFeedTradingMode(address rateFeedID) external view returns (uint256 tradingMode) {
    TradingModeInfo memory info = rateFeedTradingModes[rateFeedID];
    return info.tradingMode;
  }

  /* ==================== Check Breakers ==================== */

  /**
   * @notice Checks breakers for the rateFeedID with the specified id 
             and sets correct trading mode if any breakers are tripped
             or need to be reset.
   * @param rateFeedID The registryId of the rateFeedID to run checks for.
   */
  function checkAndSetBreakers(address rateFeedID) external {
    TradingModeInfo memory info = rateFeedTradingModes[rateFeedID];

    // This rateFeedID has not been added. So do nothing.
    if (info.lastUpdatedTime == 0) {
      return;
    }

    // Check if a breaker has non default trading mode and reset if we should.
    if (info.tradingMode != 0) {
      IBreaker breaker = IBreaker(tradingModeBreaker[info.tradingMode]);

      uint256 cooldown = breaker.getCooldown();

      // If the cooldown == 0, then a manual reset is required.
      if (((cooldown > 0) && (cooldown + info.lastUpdatedTime) <= block.timestamp)) {
        if (breaker.shouldReset(rateFeedID)) {
          info.tradingMode = 0;
          info.lastUpdatedTime = uint64(block.timestamp);
          info.lastUpdatedBlock = uint128(block.number);
          rateFeedTradingModes[rateFeedID] = info;
          emit ResetSuccessful(rateFeedID, address(breaker));
        } else {
          emit ResetAttemptCriteriaFail(rateFeedID, address(breaker));
          return;
        }
      } else {
        emit ResetAttemptNotCool(rateFeedID, address(breaker));
        return;
      }
    }

    address[] memory _breakers = breakers.getKeys();

    // Check all breakers.
    for (uint256 i = 0; i < _breakers.length; i++) {
      IBreaker breaker = IBreaker(_breakers[i]);
      bool tripBreaker = breaker.shouldTrigger(rateFeedID);
      if (tripBreaker) {
        info.tradingMode = breakerTradingMode[address(breaker)];
        info.lastUpdatedTime = uint64(block.timestamp);
        info.lastUpdatedBlock = uint128(block.number);
        rateFeedTradingModes[rateFeedID] = info;
        emit BreakerTripped(address(breaker), rateFeedID);
      }
    }
  }
}
