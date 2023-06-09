// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import { IBreakerBox } from "./interfaces/IBreakerBox.sol";
import { IBreaker } from "./interfaces/IBreaker.sol";
import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @title   BreakerBox
 * @notice  The BreakerBox checks the criteria defined in separate breaker contracts
 *          to determine whether or not buying or selling should be allowed for a
 *          specified rateFeedIDs. The contract stores references to all breakers
 *          that hold criteria to be checked, rateFeedIDs that
 *          can make use of the BreakerBox & their current trading.
 */
contract BreakerBox is IBreakerBox, Ownable {
  using SafeMath for uint256;

  /* ==================== State Variables ==================== */
  address[] public rateFeedIDs;
  // Maps a rate feed to a boolean indicating whether it has been added to the BreakerBox.
  mapping(address => bool) public rateFeedStatus;
  // Maps a rate feed to it's breakers and their breaker status. (rateFeedID => (breaker => BreakerStatus)
  mapping(address => mapping(address => BreakerStatus)) public rateFeedBreakerStatus;
  // Maps a rate feed to the associated trading mode.
  mapping(address => uint8) public rateFeedTradingMode;
  // Maps a breaker to the associated trading mode it should activate when triggered.
  mapping(address => uint8) public breakerTradingMode;
  // list of breakers to be checked.
  address[] public breakers;
  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  modifier onlyValidBreaker(address breaker, uint64 tradingMode) {
    require(!isBreaker(breaker), "This breaker has already been added");
    require(tradingMode != 0, "The default trading mode can not have a breaker");
    _;
  }

  /* ==================== Constructor ==================== */

  /**
   * @param _rateFeedIDs rateFeedIDs to be added.
   * @param _sortedOracles The address of the Celo sorted oracles contract.
   */
  constructor(address[] memory _rateFeedIDs, ISortedOracles _sortedOracles) public {
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
   * @notice Removes the specified breaker from the list of breakers
   *         and resets breakerTradingMode mapping + BreakerStatus.
   * @param breaker The address of the breaker to be removed.
   */
  function removeBreaker(address breaker) external onlyOwner {
    uint256 breakerIndex = 0;
    for (uint256 i = 0; i < breakers.length; i++) {
      if (breakers[i] == breaker) {
        breakerIndex = i;
        break;
      }
    }
    require(breakers[breakerIndex] == breaker, "Breaker has not been added");

    // for each rate feed, if breaker is enabled, disable it by calling toggleBreaker
    address[] memory activeRateFeeds = rateFeedIDs;
    for (uint256 i = 0; i < activeRateFeeds.length; i++) {
      if (rateFeedBreakerStatus[activeRateFeeds[i]][breaker].enabled) {
        toggleBreaker(breaker, activeRateFeeds[i], false);
      }
    }
    delete breakerTradingMode[breaker];
    uint256 lastIndex = breakers.length.sub(1);
    if (breakerIndex != lastIndex) {
      breakers[breakerIndex] = breakers[lastIndex];
    }
    breakers.pop();
    emit BreakerRemoved(breaker);
  }

  /**
   * @notice Enables or disables a breaker for the specified rate feed.
   * @param breakerAddress The address of the breaker.
   * @param rateFeedID The address of the rateFeed to be toggled.
   * @param enable Boolean indicating whether the breaker should be
   *               enabled or disabled for the given rateFeed.
   */
  function toggleBreaker(
    address breakerAddress,
    address rateFeedID,
    bool enable
  ) public onlyOwner {
    require(rateFeedStatus[rateFeedID], "This rate feed has not been added to the BreakerBox");
    require(isBreaker(breakerAddress), "This breaker has not been added to the BreakerBox");
    require(rateFeedBreakerStatus[rateFeedID][breakerAddress].enabled != enable, "Breaker is already in this state");
    rateFeedBreakerStatus[rateFeedID][breakerAddress].enabled = enable;
    if (enable) {
      rateFeedBreakerStatus[rateFeedID][breakerAddress].enabled = enable;
    } else {
      delete rateFeedBreakerStatus[rateFeedID][breakerAddress];
      uint8 tradingMode = calculateTradingMode(rateFeedID);
      setRateFeedTradingMode(rateFeedID, tradingMode);
    }
    emit BreakerStatusUpdated(breakerAddress, rateFeedID, enable);
  }

  /**
   * @dev This function calculates the trading mode for a given rate feed.
   *      This is done by applying a logical OR on the trading modes of all enabled breakers.
   * @param rateFeedId The address of the rate feed.
   */
  function calculateTradingMode(address rateFeedId) internal view returns (uint8) {
    uint8 tradingMode = 0;
    BreakerStatus memory _breakerStatus;
    for (uint256 i = 0; i < breakers.length; i++) {
      _breakerStatus = rateFeedBreakerStatus[rateFeedId][breakers[i]];
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
   */
  function addRateFeed(address rateFeedID) public onlyOwner {
    require(!rateFeedStatus[rateFeedID], "Rate feed ID has already been added");
    require(sortedOracles.getOracles(rateFeedID).length > 0, "Rate feed ID does not exist as it has 0 oracles");
    rateFeedIDs.push(rateFeedID);
    rateFeedStatus[rateFeedID] = true;
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
    delete rateFeedTradingMode[rateFeedID];
    deleteBreakerStatus(rateFeedID);
    rateFeedStatus[rateFeedID] = false;
    emit RateFeedRemoved(rateFeedID);
  }

  /**
   * @notice Sets the trading mode for the specified rateFeedID.
   * @param rateFeedID The address of the rateFeed.
   * @param tradingMode The trading mode that should be set.
   */
  function setRateFeedTradingMode(address rateFeedID, uint8 tradingMode) public onlyOwner {
    require(rateFeedStatus[rateFeedID], "Rate feed ID has not been added");

    rateFeedTradingMode[rateFeedID] = tradingMode;
    emit TradingModeUpdated(rateFeedID, tradingMode);
  }

  /**
   * @notice Resets all the BreakerStatus entries for the specified rateFeed.
   * @param rateFeedID The address of the rateFeed.
   */
  function deleteBreakerStatus(address rateFeedID) internal {
    for (uint256 i = 0; i < breakers.length; i++) {
      if (rateFeedBreakerStatus[rateFeedID][breakers[i]].enabled) {
        delete rateFeedBreakerStatus[rateFeedID][breakers[i]];
      }
    }
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Returns an array of breaker addresses from start to end.
   * @return An ordered list of breakers.
   */
  function getBreakers() external view returns (address[] memory) {
    return breakers;
  }

  /**
   * @notice Checks whether a breaker with the specifed address has been added.
   */
  function isBreaker(address breaker) public view returns (bool) {
    for (uint256 i = 0; i < breakers.length; i++) {
      if (breakers[i] == breaker) {
        return true;
      }
    }
    return false;
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
    return (rateFeedTradingMode[rateFeedID]);
  }

  /**
   * @notice Checks if a breaker is enabled for a specific rate feed.
   * @param breaker The address of the breaker we're checking for.
   * @param rateFeedID The address of the rateFeed.
   */
  function isBreakerEnabled(address breaker, address rateFeedID) external view returns (bool) {
    return rateFeedBreakerStatus[rateFeedID][breaker].enabled;
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
    for (uint256 i = 0; i < breakers.length; i++) {
      if (rateFeedBreakerStatus[rateFeedID][breakers[i]].enabled) {
        uint8 _breakerTradingMode = updateBreaker(rateFeedID, breakers[i]);
        _tradingMode = _tradingMode | _breakerTradingMode;
      }
    }
    rateFeedTradingMode[rateFeedID] = _tradingMode;
  }

  /**
   * @notice Gets the updated breaker trading mode for a specific rateFeed.
   * @param rateFeedID The address of the rateFeed.
   * @param breaker The address of the breaker to update.
   */
  function updateBreaker(address rateFeedID, address breaker) internal returns (uint8) {
    if (rateFeedBreakerStatus[rateFeedID][breaker].tradingMode != 0) {
      return tryResetBreaker(rateFeedID, breaker);
    } else return checkBreaker(rateFeedID, breaker);
  }

  /**
   * @notice Tries to reset a breaker if the cooldown has passed.
   * @param rateFeedID The address of the rateFeed to run checks for.
   * @param _breaker The address of the breaker to reset.
   */
  function tryResetBreaker(address rateFeedID, address _breaker) internal returns (uint8) {
    BreakerStatus memory _breakerStatus = rateFeedBreakerStatus[rateFeedID][_breaker];
    IBreaker breaker = IBreaker(_breaker);
    uint256 cooldown = breaker.getCooldown(rateFeedID);
    if ((cooldown > 0) && (cooldown.add(_breakerStatus.lastUpdatedTime) <= block.timestamp)) {
      if (breaker.shouldReset(rateFeedID)) {
        rateFeedBreakerStatus[rateFeedID][_breaker].tradingMode = 0;
        rateFeedBreakerStatus[rateFeedID][_breaker].lastUpdatedTime = uint64(block.timestamp);
        emit ResetSuccessful(rateFeedID, _breaker);
      } else emit ResetAttemptCriteriaFail(rateFeedID, _breaker);
    } else emit ResetAttemptNotCool(rateFeedID, _breaker);
    return rateFeedBreakerStatus[rateFeedID][_breaker].tradingMode;
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
      rateFeedBreakerStatus[rateFeedID][_breaker].tradingMode = tradingMode;
      rateFeedBreakerStatus[rateFeedID][_breaker].lastUpdatedTime = uint64(block.timestamp);
      emit BreakerTripped(_breaker, rateFeedID);
    }
    return tradingMode;
  }
}
