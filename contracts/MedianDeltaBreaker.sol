// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { IBreaker } from "./interfaces/IBreaker.sol";

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
contract MedianDeltaBreaker is IBreaker, Ownable {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  /* ==================== State Variables ==================== */

  // The amount of time that must pass before the breaker can be reset for a rate feed.
  // Should be set to 0 to force a manual reset.
  uint256 public cooldownTime;

  // The default allowed threshold for the median rate change as a Fixidity fraction.
  FixidityLib.Fraction public defaultRateChangeThreshold;

  // Maps rate feed to a threshold.
  mapping(address => FixidityLib.Fraction) public rateChangeThreshold;

  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  // Emitted when the default rate threshold is updated.
  event DefaultRateChangeThresholdUpdated(uint256 defaultRateChangeThreshold);

  // Emitted when the rate threshold is updated.
  event RateChangeThresholdUpdated(address rateFeedID, uint256 rateChangeThreshold);

  /* ==================== Constructor ==================== */

  constructor(
    uint256 _cooldownTime,
    uint256 _defaultRateChangeThreshold,
    address[] memory rateFeedIDs,
    uint256[] memory rateChangeThresholds,
    ISortedOracles _sortedOracles
  ) public {
    _transferOwnership(msg.sender);
    setCooldownTime(_cooldownTime);
    setDefaultRateChangeThreshold(_defaultRateChangeThreshold);
    setSortedOracles(_sortedOracles);
    setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
  }

  /* ==================== Restricted Functions ==================== */

  /**
   * @notice Sets the cooldownTime to the specified value.
   * @param _cooldownTime The new cooldownTime value.
   * @dev Should be set to 0 to force a manual reset.
   */
  function setCooldownTime(uint256 _cooldownTime) public onlyOwner {
    cooldownTime = _cooldownTime;
    emit CooldownTimeUpdated(_cooldownTime);
  }

  /**
   * @notice Sets rateChangeThreshold.
   * @param _defaultRateChangeThreshold The new rateChangeThreshold value.
   */
  function setDefaultRateChangeThreshold(uint256 _defaultRateChangeThreshold) public onlyOwner {
    defaultRateChangeThreshold = FixidityLib.wrap(_defaultRateChangeThreshold);
    require(defaultRateChangeThreshold.lt(FixidityLib.fixed1()), "rate change threshold must be less than 1");
    emit DefaultRateChangeThresholdUpdated(_defaultRateChangeThreshold);
  }

  /**
   * @notice Configures rate feed to rate shreshold pairs.
   * @param rateFeedIDs Collection of the addresses rate feeds.
   * @param rateChangeThresholds Collection of the rate thresholds.
   */
  function setRateChangeThresholds(address[] memory rateFeedIDs, uint256[] memory rateChangeThresholds)
    public
    onlyOwner
  {
    require(
      rateFeedIDs.length == rateChangeThresholds.length,
      "rate feeds and rate change thresholds have to be the same length"
    );
    for (uint256 i = 0; i < rateFeedIDs.length; i++) {
      if (rateFeedIDs[i] != address(0) && rateChangeThresholds[i] != 0) {
        FixidityLib.Fraction memory _rateChangeThreshold = FixidityLib.wrap(rateChangeThresholds[i]);
        require(sortedOracles.getOracles(rateFeedIDs[i]).length > 0, "rate feed ID does not exist as it has 0 oracles");
        require(_rateChangeThreshold.lt(FixidityLib.fixed1()), "rate change threshold must be less than 1");
        rateChangeThreshold[rateFeedIDs[i]] = _rateChangeThreshold;
        emit RateChangeThresholdUpdated(rateFeedIDs[i], rateChangeThresholds[i]);
      }
    }
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
  function shouldTrigger(address rateFeedID) public view returns (bool triggerBreaker) {
    uint256 previousMedian = sortedOracles.previousMedianRate(rateFeedID);
    if (previousMedian == 0) {
      // Previous median will be 0 if this rate feed is new and has not had at least two median updates yet.
      return false;
    }

    (uint256 currentMedian, ) = sortedOracles.medianRate(rateFeedID);

    // Check if current median is within allowed threshold of last median
    triggerBreaker = !isWithinThreshold(previousMedian, currentMedian, rateFeedID);
  }

  /**
   * @notice  Checks whether or not the conditions have been met
   *          for the specifed rate feed to be reset.
   * @return  resetBreaker A bool indicating whether or not
   *          this breaker can be reset for the given rate feed.
   */
  function shouldReset(address rateFeedID) external view returns (bool resetBreaker) {
    return !shouldTrigger(rateFeedID);
  }

  /**
   * @notice Checks if the specified current median rate is within the allowed threshold.
   * @param prevRate The previous median rate.
   * @param currentRate The current median rate.
   * @param rateFeedID The specific rate ID to check threshold for.
   * @return  Returns a bool indicating whether or not the current rate
   *          is within the allowed threshold.
   */
  function isWithinThreshold(
    uint256 prevRate,
    uint256 currentRate,
    address rateFeedID
  ) public view returns (bool) {
    uint256 allowedThreshold = defaultRateChangeThreshold.unwrap();

    uint256 rateSpecificThreshold = rateChangeThreshold[rateFeedID].unwrap();

    // checks if a given rate feed id has a threshold set and reassignes it
    if (rateSpecificThreshold != 0) allowedThreshold = rateSpecificThreshold;

    uint256 fixed1 = FixidityLib.fixed1().unwrap();

    uint256 maxPercent = uint256(fixed1).add(allowedThreshold);
    uint256 maxValue = (prevRate.mul(maxPercent)).div(10**24);

    uint256 minPercent = uint256(fixed1).sub(allowedThreshold);
    uint256 minValue = (prevRate.mul(minPercent)).div(10**24);

    return (currentRate >= minValue && currentRate <= maxValue);
  }
}
