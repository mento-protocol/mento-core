// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { IBreaker } from "./interfaces/IBreaker.sol";
import { WithCooldown } from "./common/breakers/WithCooldown.sol";
import { WithThreshold } from "./common/breakers/WithThreshold.sol";

import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { FixidityLib } from "./common/FixidityLib.sol";

/**
 * @title   Median Delta Breaker
 * @notice  Breaker contract that will trigger when an updated oracle median rate changes
 *          more than a configured relative threshold from the previous one. If this
 *          breaker is triggered for a rate feed it should be set to no trading mode.
 */
contract MedianDeltaBreaker is IBreaker, WithCooldown, WithThreshold, Ownable {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  /* ==================== State Variables ==================== */
  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  // The previous median recorded for a ratefeed.
  mapping(address => uint256) public previousMedianRates;

  /* ==================== Constructor ==================== */

  constructor(
    uint256 _defaultCooldownTime,
    uint256 _defaultRateChangeThreshold,
    ISortedOracles _sortedOracles,
    address[] memory rateFeedIDs,
    uint256[] memory rateChangeThresholds,
    uint256[] memory cooldownTimes
  ) public {
    _transferOwnership(msg.sender);
    setSortedOracles(_sortedOracles);

    _setDefaultCooldownTime(_defaultCooldownTime);
    _setDefaultRateChangeThreshold(_defaultRateChangeThreshold);
    _setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
    _setCooldownTimes(rateFeedIDs, cooldownTimes);
  }

  /* ==================== Restricted Functions ==================== */

  /**
   * @notice Sets the cooldown time to the specified value for a rate feed.
   * @param rateFeedIDs the targeted rate feed.
   * @param cooldownTimes The new cooldownTime value.
   * @dev Should be set to 0 to force a manual reset.
   */
  function setCooldownTime(address[] calldata rateFeedIDs, uint256[] calldata cooldownTimes) external onlyOwner {
    _setCooldownTimes(rateFeedIDs, cooldownTimes);
  }

  /**
   * @notice Sets the cooldownTime to the specified value for a rate feed.
   * @param cooldownTime The new cooldownTime value.
   * @dev Should be set to 0 to force a manual reset.
   */
  function setDefaultCooldownTime(uint256 cooldownTime) external onlyOwner {
    _setDefaultCooldownTime(cooldownTime);
  }

  /**
   * @notice Sets rateChangeThreshold.
   * @param _defaultRateChangeThreshold The new rateChangeThreshold value.
   */
  function setDefaultRateChangeThreshold(uint256 _defaultRateChangeThreshold) external onlyOwner {
    _setDefaultRateChangeThreshold(_defaultRateChangeThreshold);
  }

  /**
   * @notice Configures rate feed to rate shreshold pairs.
   * @param rateFeedIDs Collection of the addresses rate feeds.
   * @param rateChangeThresholds Collection of the rate thresholds.
   */
  function setRateChangeThresholds(address[] calldata rateFeedIDs, uint256[] calldata rateChangeThresholds)
    external
    onlyOwner
  {
    _setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
  }

  /**
   * @notice Sets the address of the sortedOracles contract.
   * @param _sortedOracles The new address of the sorted oracles contract.
   */
  function setSortedOracles(ISortedOracles _sortedOracles) public onlyOwner {
    require(address(_sortedOracles) != address(0), "SortedOracles address must be set");
    sortedOracles = _sortedOracles;
    emit SortedOraclesUpdated(address(_sortedOracles));
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Gets the cooldown time for the breaker.
   * @return Returns the time in seconds.
   */
  function getCooldown() external view returns (uint256) {
    return cooldownTime;
  }

  /**
   * @notice  Check if the current median report rate for a rate feed change, relative
   *          to the last median report, is greater than the configured threshold.
   *          If the change is greater than the threshold the breaker will trip.
   * @param   rateFeedID The rate feed to be checked.
   * @return  triggerBreaker  A bool indicating whether or not this breaker
   *                          should be tripped for the rate feed.
   */
  function shouldTrigger(address rateFeedID) public returns (bool triggerBreaker) {
    (uint256 currentMedian, ) = sortedOracles.medianRate(rateFeedID);

    uint256 previousMedian = previousMedianRates[rateFeedID];
    previousMedianRates[rateFeedID] = currentMedian;

    if (previousMedian == 0) {
      // Previous median will be 0 the first time rate is checked.
      return false;
    }

    return exceedsThreshold(previousMedian, currentMedian, rateFeedID);
  }

  /**
   * @notice  Checks whether or not the conditions have been met
   *          for the specifed rate feed to be reset.
   * @return  resetBreaker A bool indicating whether or not
   *          this breaker can be reset for the given rate feed.
   */
  function shouldReset(address rateFeedID) external returns (bool resetBreaker) {
    return !shouldTrigger(rateFeedID);
  }
}
