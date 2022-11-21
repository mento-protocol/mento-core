// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { IBreaker } from "./interfaces/IBreaker.sol";
import { ISortedOracles } from "./interfaces/ISortedOracles.sol";

import { UsingRegistry } from "./common/UsingRegistry.sol";
import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { FixidityLib } from "./common/FixidityLib.sol";

/**
 * @title   Median Delta Breaker
 * @notice  Breaker contract that will trigger when the current oracle median price change
 *          relative to the last is greater than a calculated threshold. If this
 *          breaker is triggered for a rate feed it should be set to no trading mode.
 */
contract MedianDeltaBreaker is IBreaker, Ownable {
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;

  /* ==================== State Variables ==================== */

  // The amount of time that must pass before the breaker can be reset for a rate feed.
  // Should be set to 0 to force a manual reset.
  uint256 public cooldownTime;
  // The allowed threshold for the median price change as a Fixidity fraction.
  FixidityLib.Fraction public priceChangeThreshold;

  // Address of the Mento SortedOracles contract
  ISortedOracles public sortedOracles;

  /* ==================== Events ==================== */

  event PriceChangeThresholdUpdated(uint256 newPriceChangeThreshold);

  /* ==================== Constructor ==================== */

  constructor(
    uint256 _cooldownTime,
    uint256 _priceChangeThreshold,
    ISortedOracles _sortedOracles
  ) public {
    _transferOwnership(msg.sender);
    setCooldownTime(_cooldownTime);
    setPriceChangeThreshold(_priceChangeThreshold);
    setSortedOracles(_sortedOracles);
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
   * @notice Sets priceChangeThreshold.
   * @param _priceChangeThreshold The new priceChangeThreshold value.
   */
  function setPriceChangeThreshold(uint256 _priceChangeThreshold) public onlyOwner {
    priceChangeThreshold = FixidityLib.wrap(_priceChangeThreshold);
    require(priceChangeThreshold.lt(FixidityLib.fixed1()), "price change threshold must be less than 1");
    emit PriceChangeThresholdUpdated(_priceChangeThreshold);
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
   * @notice  Check if the current median report price change, for a rate feed, relative
   *          to the last median report is greater than a calculated threshold.
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
    triggerBreaker = !isWithinThreshold(previousMedian, currentMedian);
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
   * @return  Returns a bool indicating whether or not the current rate
   *          is within the allowed threshold.
   */
  function isWithinThreshold(uint256 prevRate, uint256 currentRate) public view returns (bool) {
    uint256 allowedThreshold = priceChangeThreshold.unwrap();
    uint256 fixed1 = FixidityLib.fixed1().unwrap();

    uint256 maxPercent = uint256(fixed1).add(allowedThreshold);
    uint256 maxValue = (prevRate.mul(maxPercent)).div(10**24);

    uint256 minPercent = uint256(fixed1).sub(allowedThreshold);
    uint256 minValue = (prevRate.mul(minPercent)).div(10**24);

    return (currentRate >= minValue && currentRate <= maxValue);
  }
}
