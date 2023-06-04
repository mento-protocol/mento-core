// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import { IBreakerBox } from "./interfaces/IBreakerBox.sol";
import { IBreaker } from "./interfaces/IBreaker.sol";
import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
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
  using SafeMath for uint256;

  /* ==================== State Variables ==================== */
  address[] public rateFeedIDs;
  // Maps a rate feed to it's breakers and their breaker status.
  mapping(address => mapping(address => BreakerStatus)) public breakerStatus;
  // Maps a rate feed to the associated trading mode.
  mapping(address => uint8) public tradingModes;
  // Maps a breaker to the associated trading mode.
  mapping(address => uint8) public breakerTradingMode;
  // Ordered list of breakers to be checked.
  LinkedList.List private breakers;
  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  modifier onlyValidBreaker(address breaker, uint64 tradingMode) {
    require(!isBreaker(breaker), "This breaker has already been added");
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
   * @notice Adds a breaker to the end of the list of breakers & the breakerTradingMode mapping.
   * @param breaker The address of the breaker to be added.
   * @param tradingMode The trading mode of the breaker to be added.
   */
  function addBreaker(address breaker, uint8 tradingMode) public onlyOwner onlyValidBreaker(breaker, tradingMode) {
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
    uint8 tradingMode,
    address prevBreaker,
    address nextBreaker
  ) external onlyOwner onlyValidBreaker(breaker, tradingMode) {
    breakerTradingMode[breaker] = tradingMode;
    breakers.insert(breaker, prevBreaker, nextBreaker);
    emit BreakerAdded(breaker);
  }

  /**
   * @notice Removes the specified breaker from the list of breakers
   *         and resets breakerTradingMode mapping + BreakerStatus.
   * @param breaker The address of the breaker to be removed.
   */
  function removeBreaker(address breaker) external onlyOwner {
    require(isBreaker(breaker), "This breaker has not been added");

    address[] memory activeRateFeeds = rateFeedIDs;
    for (uint256 i = 0; i < activeRateFeeds.length; i++) {
      if (breakerStatus[activeRateFeeds[i]][breaker].enabled) {
        toggleBreaker(breaker, activeRateFeeds[i], false);
      }
    }
    delete breakerTradingMode[breaker];
    breakers.remove(breaker);
    emit BreakerRemoved(breaker);
  }

  /**
   * @notice Enables or disables a breaker for the specified rate feed.
   * @param breakerAddress The address of the breaker.
   * @param rateFeedId The address of the rateFeed to be toggled.
   * @param enable Boolean indicating whether the breaker should be
   *               enabled or disabled for the given rateFeed.
   */
  function toggleBreaker(
    address breakerAddress,
    address rateFeedId,
    bool enable
  ) public onlyOwner {
    require(breakerStatus[rateFeedId][address(0)].enabled, "This rate feed has not been added to the BreakerBox");
    require(isBreaker(breakerAddress), "This breaker has not been added to the BreakerBox");
    require(breakerStatus[rateFeedId][breakerAddress].enabled != enable, "Breaker is already in this state");
    breakerStatus[rateFeedId][breakerAddress].enabled = enable;
    if (!enable) {
      delete breakerStatus[rateFeedId][breakerAddress];
      uint8 tradingMode = calculateTradingMode(rateFeedId);
      setRateFeedTradingMode(rateFeedId, tradingMode);
    }
    emit BreakerStatusUpdated(breakerAddress, rateFeedId, enable);
  }

  /**
   * @notice Helper function:
   *         Calculates the current trading mode for a rate feed.
   * @param rateFeedId The address of the rate feed.
   */
  function calculateTradingMode(address rateFeedId) internal view returns (uint8) {
    uint8 tradingMode = 0;
    BreakerStatus memory _breakerStatus;
    address[] memory _breakers = breakers.getKeys();
    for (uint256 i = 0; i < _breakers.length; i++) {
      _breakerStatus = breakerStatus[rateFeedId][_breakers[i]];
      if (_breakerStatus.enabled) {
        tradingMode = tradingMode | _breakerStatus.tradingMode;
      }
    }
    return tradingMode;
  }

  /* ---------- rateFeedIDs ---------- */

  /**
   * @notice Adds a rateFeedID to the mapping of monitored rateFeedIDs.
   * @param rateFeedID The address of the rateFeed to be added.
   * @dev The rateFeedID & 0 address is used to set a rateFeed active
   *      or inactive in the breakerStatus mapping.
   */
  function addRateFeed(address rateFeedID) public onlyOwner {
    require(!breakerStatus[rateFeedID][address(0)].enabled, "Rate feed ID has already been added");
    require(sortedOracles.getOracles(rateFeedID).length > 0, "Rate feed ID does not exist as it has 0 oracles");
    rateFeedIDs.push(rateFeedID);
    breakerStatus[rateFeedID][address(0)].enabled = true;
    emit RateFeedAdded(rateFeedID);
  }

  /**
   * @notice Adds the specified rateFeedIDs to the mapping of monitored rateFeedIDs.
   * @param newRateFeedIDs The array of rateFeed addresses to be added.
   */
  function addRateFeeds(address[] memory newRateFeedIDs) public onlyOwner {
    for (uint256 i = 0; i < newRateFeedIDs.length; i++) {
      addRateFeed(newRateFeedIDs[i]);
    }
  }

  /**
   * @notice Removes a rateFeedID from the mapping of monitored rateFeedIDs
   *          and resets all the BreakerStatus entries for that rateFeed.
   * @param rateFeedID The address of the rateFeed to be removed.
   */
  function removeRateFeed(address rateFeedID) external onlyOwner {
    uint256 rateFeedIndex = 0;
    for (uint256 i = 0; i < rateFeedIDs.length; i++) {
      if (rateFeedIDs[i] == rateFeedID) {
        rateFeedIndex = i;
        break;
      }
    }
    require(rateFeedIDs[rateFeedIndex] == rateFeedID, "Rate feed ID has not been added");

    uint256 lastIndex = rateFeedIDs.length.sub(1);
    if (rateFeedIndex != lastIndex) {
      rateFeedIDs[rateFeedIndex] = rateFeedIDs[lastIndex];
    }
    rateFeedIDs.pop();
    delete tradingModes[rateFeedID];
    deleteBreakerStatus(rateFeedID);
    breakerStatus[rateFeedID][address(0)].enabled = false;
    emit RateFeedRemoved(rateFeedID);
  }

  /**
   * @notice Sets the trading mode for the specified rateFeedID.
   * @param rateFeedID The address of the rateFeed.
   * @param tradingMode The trading mode that should be set.
   */
  function setRateFeedTradingMode(address rateFeedID, uint8 tradingMode) public onlyOwner {
    require(breakerStatus[rateFeedID][address(0)].enabled, "Rate feed ID has not been added");

    tradingModes[rateFeedID] = tradingMode;
    emit TradingModeUpdated(rateFeedID, tradingMode);
  }

  /**
   * @notice Helper function:
   *         Resets all the BreakerStatus entries for the specified rateFeed.
   * @param rateFeedID The address of the rateFeed.
   */
  function deleteBreakerStatus(address rateFeedID) internal {
    address[] memory _breakers = breakers.getKeys();
    for (uint256 i = 0; i < _breakers.length; i++) {
      if (breakerStatus[rateFeedID][_breakers[i]].enabled) {
        delete breakerStatus[rateFeedID][_breakers[i]];
      }
    }
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
  function getRateFeeds() external view returns (address[] memory) {
    return rateFeedIDs;
  }

  /**
   * @notice Returns the trading mode for the specified rateFeedID.
   * @param rateFeedID The address of the rateFeed to retrieve the trading mode for.
   */
  function getRateFeedTradingMode(address rateFeedID) external view returns (uint8 tradingMode) {
    return (tradingModes[rateFeedID]);
  }

  /**
   * @notice Checks if a breaker is enabled for a specific rate feed.
   * @param breaker The address of the breaker we're checking for.
   * @param rateFeedID The address of the rateFeed.
   */
  function isBreakerEnabled(address breaker, address rateFeedID) external view returns (bool) {
    return breakerStatus[rateFeedID][breaker].enabled;
  }

  /* ==================== Check Breakers ==================== */

  /**
   * @notice Checks breakers for the rateFeedID with the specified id 
             and sets correct trading mode if any breakers are tripped
             or need to be reset.
   * @param rateFeedID The address of the rateFeed to run checks for.
   */
  function checkAndSetBreakers(address rateFeedID) external {
    uint8 _tradingMode = 0;
    address[] memory _breakers = breakers.getKeys();
    for (uint256 i = 0; i < _breakers.length; i++) {
      if (breakerStatus[rateFeedID][_breakers[i]].enabled) {
        uint8 _breakerTradingMode = updateBreaker(rateFeedID, _breakers[i]);
        _tradingMode = _tradingMode | _breakerTradingMode;
      }
    }
    tradingModes[rateFeedID] = _tradingMode;
  }

  /**
   * @notice Gets the updated breaker trading mode for a specific rateFeed.
   * @param rateFeedID The address of the rateFeed.
   * @param breaker The address of the breaker to update.
   */
  function updateBreaker(address rateFeedID, address breaker) internal returns (uint8) {
    if (breakerStatus[rateFeedID][breaker].tradingMode != 0) {
      return tryResetBreaker(rateFeedID, breaker);
    } else return checkBreaker(rateFeedID, breaker);
  }

  /**
   * @notice Tries to reset a breaker if the cooldown has passed.
   * @param rateFeedID The address of the rateFeed to run checks for.
   * @param _breaker The address of the breaker to reset.
   */
  function tryResetBreaker(address rateFeedID, address _breaker) internal returns (uint8) {
    BreakerStatus memory _breakerStatus = breakerStatus[rateFeedID][_breaker];
    IBreaker breaker = IBreaker(_breaker);
    uint256 cooldown = breaker.getCooldown(rateFeedID);
    if ((cooldown > 0) && (cooldown.add(_breakerStatus.lastUpdatedTime) <= block.timestamp)) {
      if (breaker.shouldReset(rateFeedID)) {
        breakerStatus[rateFeedID][_breaker].tradingMode = 0;
        breakerStatus[rateFeedID][_breaker].lastUpdatedTime = uint64(block.timestamp);
        emit ResetSuccessful(rateFeedID, _breaker);
      } else emit ResetAttemptCriteriaFail(rateFeedID, _breaker);
    } else emit ResetAttemptNotCool(rateFeedID, _breaker);
    return breakerStatus[rateFeedID][_breaker].tradingMode;
  }

  /**
   * @notice Checks if a breaker tripped.
   * @param rateFeedID The address of the rateFeed to run checks for.
   * @param _breaker The address of the breaker to check.
   */
  function checkBreaker(address rateFeedID, address _breaker) internal returns (uint8) {
    uint8 tradingMode = 0;
    IBreaker breaker = IBreaker(_breaker);
    if (breaker.shouldTrigger(rateFeedID)) {
      tradingMode = breakerTradingMode[_breaker];
      breakerStatus[rateFeedID][_breaker].tradingMode = tradingMode;
      breakerStatus[rateFeedID][_breaker].lastUpdatedTime = uint64(block.timestamp);
      emit BreakerTripped(_breaker, rateFeedID);
    }
    return tradingMode;
  }
}
