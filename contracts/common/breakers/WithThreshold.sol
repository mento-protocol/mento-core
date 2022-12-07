// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { FixidityLib } from "../FixidityLib.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
 * @title   Breaker With Thershold
 * @notice  Utility portion of a Breaker contract which deals with
 *          managing a threshold percentage and checking two values
 * .        against it.
 */
contract WithThreshold {
  using FixidityLib for FixidityLib.Fraction;
  using SafeMath for uint256;

  /* ==================== Events ==================== */

  // Emitted when the default rate threshold is updated.
  event DefaultRateChangeThresholdUpdated(uint256 defaultRateChangeThreshold);

  // Emitted when the rate threshold is updated.
  event RateChangeThresholdUpdated(address rateFeedID, uint256 rateChangeThreshold);

  /* ==================== State Variables ==================== */

  // The default allowed threshold for the median rate change as a Fixidity fraction.
  FixidityLib.Fraction public defaultRateChangeThreshold;

  // Maps rate feed to a threshold.
  mapping(address => FixidityLib.Fraction) public rateChangeThreshold;

  /* ==================== Restricted Functions ==================== */

  /**
   * @notice Sets rateChangeThreshold.
   * @param _defaultRateChangeThreshold The new rateChangeThreshold value.
   */
  function _setDefaultRateChangeThreshold(uint256 _defaultRateChangeThreshold) internal {
    defaultRateChangeThreshold = FixidityLib.wrap(_defaultRateChangeThreshold);
    require(defaultRateChangeThreshold.lt(FixidityLib.fixed1()), "value must be less than 1");
    emit DefaultRateChangeThresholdUpdated(_defaultRateChangeThreshold);
  }

  /**
   * @notice Configures rate feed to rate shreshold pairs.
   * @param rateFeedIDs Collection of the addresses rate feeds.
   * @param rateChangeThresholds Collection of the rate thresholds.
   */
  function _setRateChangeThresholds(address[] memory rateFeedIDs, uint256[] memory rateChangeThresholds) internal {
    require(rateFeedIDs.length == rateChangeThresholds.length, "array length missmatch");
    for (uint256 i = 0; i < rateFeedIDs.length; i++) {
      require(rateFeedIDs[i] != address(0), "rate feed invalid");
      FixidityLib.Fraction memory _rateChangeThreshold = FixidityLib.wrap(rateChangeThresholds[i]);
      require(_rateChangeThreshold.lt(FixidityLib.fixed1()), "value must be less than 1");
      rateChangeThreshold[rateFeedIDs[i]] = _rateChangeThreshold;
      emit RateChangeThresholdUpdated(rateFeedIDs[i], rateChangeThresholds[i]);
    }
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Checks if the specified current median rate exceeds the allowed threshold.
   * @param prevRate The previous median rate.
   * @param currentRate The current median rate.
   * @param rateFeedID The specific rate ID to check threshold for.
   * @return  Returns a bool indicating whether or not the current rate
   *          is within the allowed threshold.
   */
  function exceedsThreshold(
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

    return (currentRate < minValue || currentRate > maxValue);
  }
}
