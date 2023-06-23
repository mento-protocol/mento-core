// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
import { console2 as console } from "forge-std/console2.sol";

import { BaseTest } from "../../utils/BaseTest.t.sol";
import { MockSortedOracles } from "../../mocks/MockSortedOracles.sol";

import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { SortedLinkedListWithMedian } from "contracts/common/linkedlists/SortedLinkedListWithMedian.sol";
import { MedianDeltaBreaker } from "contracts/oracles/breakers/MedianDeltaBreaker.sol";

contract MedianDeltaBreakerTest is BaseTest {
  address notDeployer;

  address rateFeedID1;
  address rateFeedID2;
  address rateFeedID3;
  MockSortedOracles sortedOracles;
  MedianDeltaBreaker breaker;

  uint256 defaultThreshold = 0.15 * 10**24; // 15%
  uint256 defaultCooldownTime = 5 minutes;

  address[] rateFeedIDs = new address[](1);
  uint256[] rateChangeThresholds = new uint256[](1);
  uint256[] cooldownTimes = new uint256[](1);

  event BreakerTriggered(address indexed rateFeedID);
  event BreakerReset(address indexed rateFeedID);
  event DefaultCooldownTimeUpdated(uint256 newCooldownTime);
  event CooldownTimeUpdated(address indexed rateFeedID, uint256 newCooldownTime);
  event DefaultRateChangeThresholdUpdated(uint256 newMinRateChangeThreshold);
  event SortedOraclesUpdated(address newSortedOracles);
  event RateChangeThresholdUpdated(address rateFeedID1, uint256 rateChangeThreshold);
  event SmoothingFactorSet(address rateFeedId, uint256 newSmoothingFactor);

  function setUp() public {
    notDeployer = actor("notDeployer");
    rateFeedID1 = actor("rateFeedID1");
    rateFeedID2 = actor("rateFeedID2");
    rateFeedID3 = actor("rateFeedID3");

    rateFeedIDs[0] = rateFeedID2;
    rateChangeThresholds[0] = 0.9 * 10**24;
    cooldownTimes[0] = 10 minutes;

    vm.startPrank(deployer);
    sortedOracles = new MockSortedOracles();

    sortedOracles.addOracle(rateFeedID1, actor("OracleClient"));
    sortedOracles.addOracle(rateFeedID2, actor("oracleClient"));
    sortedOracles.addOracle(rateFeedID3, actor("oracleClient1"));

    breaker = new MedianDeltaBreaker(
      defaultCooldownTime,
      defaultThreshold,
      ISortedOracles(address(sortedOracles)),
      rateFeedIDs,
      rateChangeThresholds,
      cooldownTimes
    );
  }
}

contract MedianDeltaBreakerTest_constructorAndSetters is MedianDeltaBreakerTest {
  /* ---------- Constructor ---------- */

  function test_constructor_shouldSetOwner() public {
    assertEq(breaker.owner(), deployer);
  }

  function test_constructor_shouldSetDefaultCooldownTime() public {
    assertEq(breaker.defaultCooldownTime(), defaultCooldownTime);
  }

  function test_constructor_shouldSetDefaultRateChangeThreshold() public {
    assertEq(breaker.defaultRateChangeThreshold(), defaultThreshold);
  }

  function test_constructor_shouldSetSortedOracles() public {
    assertEq(address(breaker.sortedOracles()), address(sortedOracles));
  }

  function test_constructor_shouldSetRateChangeThresholds() public {
    assertEq(breaker.rateChangeThreshold(rateFeedIDs[0]), rateChangeThresholds[0]);
  }

  function test_constructor_shouldSetCooldownTimes() public {
    assertEq(breaker.getCooldown(rateFeedIDs[0]), cooldownTimes[0]);
  }

  /* ---------- Setters ---------- */

  function test_setDefaultCooldownTime_whenCallerIsNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(notDeployer);
    breaker.setDefaultCooldownTime(2 minutes);
  }

  function test_setDefaultCooldownTime_whenCallerIsOwner_shouldUpdateAndEmit() public {
    uint256 testCooldown = 39 minutes;
    vm.expectEmit(false, false, false, true);
    emit DefaultCooldownTimeUpdated(testCooldown);
    breaker.setDefaultCooldownTime(testCooldown);
  }

  function test_setRateChangeThreshold_whenCallerIsNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(notDeployer);

    breaker.setDefaultRateChangeThreshold(123456);
  }

  function test_setRateChangeThreshold_whenValueGreaterThanOne_shouldRevert() public {
    vm.expectRevert("value must be less than 1");
    breaker.setDefaultRateChangeThreshold(1 * 10**24);
  }

  function test_setRateChangeThreshold_whenCallerIsOwner_shouldUpdateAndEmit() public {
    uint256 testThreshold = 0.1 * 10**24;
    vm.expectEmit(false, false, false, true);
    emit DefaultRateChangeThresholdUpdated(testThreshold);

    breaker.setDefaultRateChangeThreshold(testThreshold);

    assertEq(breaker.defaultRateChangeThreshold(), testThreshold);
  }

  function test_setSortedOracles_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breaker.setSortedOracles(ISortedOracles(address(0)));
  }

  function test_setSortedOracles_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("SortedOracles address must be set");
    breaker.setSortedOracles(ISortedOracles(address(0)));
  }

  function test_setSortedOracles_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newSortedOracles = actor("newSortedOracles");
    vm.expectEmit(true, true, true, true);
    emit SortedOraclesUpdated(newSortedOracles);

    breaker.setSortedOracles(ISortedOracles(newSortedOracles));

    assertEq(address(breaker.sortedOracles()), newSortedOracles);
  }

  function test_setRateChangeThreshold_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
  }

  function test_setRateChangeThreshold_whenValuesAreDifferentLengths_shouldRevert() public {
    address[] memory rateFeedIDs2 = new address[](2);
    rateFeedIDs2[0] = actor("randomRateFeed");
    rateFeedIDs2[1] = actor("randomRateFeed2");
    vm.expectRevert("array length missmatch");
    breaker.setRateChangeThresholds(rateFeedIDs2, rateChangeThresholds);
  }

  function test_setRateChangeThreshold_whenThresholdIsExactly1_shouldRevert() public {
    rateChangeThresholds[0] = 1 * 10**24;
    vm.expectRevert("value must be less than 1");
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
  }

  function test_setRateChangeThreshold_whenSenderIsOwner_shouldUpdateAndEmit() public {
    vm.expectEmit(true, true, true, true);
    emit RateChangeThresholdUpdated(rateFeedIDs[0], rateChangeThresholds[0]);
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
    assertEq(breaker.rateChangeThreshold(rateFeedIDs[0]), rateChangeThresholds[0]);
  }

  function test_setSmoothingFactor_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breaker.setSmoothingFactor(rateFeedIDs[0], 0.8 * 1e24);
  }

  function test_setSmoothingFactor_whenValueIsMoreThan1_shouldRevert() public {
    vm.expectRevert("Smoothing factor must be <= 1");
    breaker.setSmoothingFactor(rateFeedIDs[0], 1.1 * 1e24);
  }

  function test_setSmoothingFactor_whenSenderIsOwner_shouldUpdateAndEmit() public {
    vm.expectEmit(true, true, true, true);
    emit SmoothingFactorSet(rateFeedIDs[0], 0.05 * 1e24);
    breaker.setSmoothingFactor(rateFeedIDs[0], 0.05 * 1e24);

    vm.expectEmit(true, true, true, true);
    emit SmoothingFactorSet(rateFeedIDs[0], 1 * 1e24);
    breaker.setSmoothingFactor(rateFeedIDs[0], 1 * 1e24);
  }

  /* ---------- Getters ---------- */
  function test_getCooldown_withDefault_shouldReturnDefaultCooldown() public {
    assertEq(breaker.getCooldown(rateFeedID1), defaultCooldownTime);
  }

  function test_getCooldown_withoutdefault_shouldReturnSpecificCooldown() public {
    assertEq(breaker.getCooldown(rateFeedIDs[0]), cooldownTimes[0]);
  }

  function test_getSmoothingFactor_whenNotSet_shouldReturnDefaultSmoothingFactor() public {
    assertEq(breaker.getSmoothingFactor(rateFeedIDs[0]), 1e24);
  }

  function test_getSmoothingFactor_whenSet_shouldReturnSetSmoothingFactor() public {
    uint256 smoothingFactor = 0.02 * 1e24;
    breaker.setSmoothingFactor(rateFeedIDs[0], smoothingFactor);
    assertEq(breaker.getSmoothingFactor(rateFeedIDs[0]), smoothingFactor);
  }
}

contract MedianDeltaBreakerTest_shouldTrigger is MedianDeltaBreakerTest {
  function setSortedOraclesMedian(uint256 median) public {
    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(sortedOracles.medianRate.selector),
      abi.encode(median, 1)
    );
  }

  function updatePreviousEMAByPercent(uint256 medianChangeScaleFactor, address _rateFeedID) public {
    uint256 previousEMA = 0.98 * 10**24;
    uint256 currentMedianRate = (previousEMA * medianChangeScaleFactor) / 10**24;
    stdstore.target(address(breaker)).sig(breaker.medianRatesEMA.selector).with_key(_rateFeedID).checked_write(
      previousEMA
    );

    setSortedOraclesMedian(currentMedianRate);
    vm.expectCall(address(sortedOracles), abi.encodeWithSelector(sortedOracles.medianRate.selector, _rateFeedID));
  }

  function test_shouldTrigger_withDefaultThreshold_shouldTrigger() public {
    assertEq(breaker.rateChangeThreshold(rateFeedID1), 0);
    updatePreviousEMAByPercent(0.7 * 10**24, rateFeedID1);
    assertTrue(breaker.shouldTrigger(rateFeedID1));
  }

  function test_shouldTrigger_whenThresholdIsLargerThanMedian_shouldNotTrigger() public {
    updatePreviousEMAByPercent(0.7 * 10**24, rateFeedID1);

    rateChangeThresholds[0] = 0.8 * 10**24;
    rateFeedIDs[0] = rateFeedID1;
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
    assertEq(breaker.rateChangeThreshold(rateFeedID1), rateChangeThresholds[0]);

    assertFalse(breaker.shouldTrigger(rateFeedID1));
  }

  function test_shouldTrigger_whithDefaultThreshold_ShouldNotTrigger() public {
    assertEq(breaker.rateChangeThreshold(rateFeedID3), 0);

    updatePreviousEMAByPercent(1.1 * 10**24, rateFeedID3);

    assertFalse(breaker.shouldTrigger(rateFeedID3));
  }

  function test_shouldTrigger_whenThresholdIsSmallerThanMedian_ShouldTrigger() public {
    updatePreviousEMAByPercent(1.1 * 10**24, rateFeedID3);
    rateChangeThresholds[0] = 0.01 * 10**24;
    rateFeedIDs[0] = rateFeedID3;
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
    assertEq(breaker.rateChangeThreshold(rateFeedID3), rateChangeThresholds[0]);

    assertTrue(breaker.shouldTrigger(rateFeedID3));
  }

  function test_shouldTrigger_whenFirstMedianIsReported_EMAShouldBeEqual() public {
    address rateFeed = rateFeedIDs[0];
    assertEq(breaker.medianRatesEMA(rateFeed), 0);

    (uint256 beforeRate, ) = sortedOracles.medianRate(rateFeed);
    assertEq(beforeRate, 0);

    uint256 median = 0.9836 * 10**24;
    setSortedOraclesMedian(median);

    (uint256 afterRate, ) = sortedOracles.medianRate(rateFeed);
    assertEq(afterRate, median);

    assertFalse(breaker.shouldTrigger(rateFeed));
    assertEq(breaker.medianRatesEMA(rateFeed), median);
  }

  function test_shouldTrigger_whenMedianDrops_shouldCalculateEMACorrectlyAndTrigger() public {
    address rateFeed = rateFeedIDs[0];
    uint256 smoothingFactor = 0.1 * 10**24;
    rateChangeThresholds[0] = 0.03 * 10**24;
    rateFeedIDs[0] = rateFeed;
    breaker.setSmoothingFactor(rateFeed, smoothingFactor);
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);

    uint256 firstMedian = 1.05 * 10**24;
    setSortedOraclesMedian(firstMedian);
    assertFalse(breaker.shouldTrigger(rateFeed));
    assertEq(breaker.medianRatesEMA(rateFeed), firstMedian);

    uint256 secondMedian = 1.0164 * 10**24;
    setSortedOraclesMedian(secondMedian);
    bool triggered = breaker.shouldTrigger((rateFeed));

    // 0.1*1.0164 + (1.05 * 0.9) = 1.04664
    assertEq(breaker.medianRatesEMA(rateFeed), 1.04664 * 10**24);

    // (1.0164-1.05)/1.05 = -0.03200000000000007
    assertTrue(triggered);
  }

  function test_shouldTrigger_whenMedianJumps_shouldCalculateEMACorrectlyAndTrigger() public {
    address rateFeed = rateFeedIDs[0];
    uint256 smoothingFactor = 0.1 * 10**24;
    rateChangeThresholds[0] = 0.03 * 10**24;
    rateFeedIDs[0] = rateFeed;
    breaker.setSmoothingFactor(rateFeed, smoothingFactor);
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);

    uint256 firstMedian = 1.05 * 10**24;
    setSortedOraclesMedian(firstMedian);
    assertFalse(breaker.shouldTrigger(rateFeed));
    assertEq(breaker.medianRatesEMA(rateFeed), firstMedian);

    uint256 secondMedian = 1.0836 * 10**24;
    setSortedOraclesMedian(secondMedian);
    bool triggered = breaker.shouldTrigger((rateFeed));

    // 0.1*1.0836 + (1.05 * 0.9) = 1.05336
    assertEq(breaker.medianRatesEMA(rateFeed), 1.05336 * 10**24);

    // (1.0836-1.05)/1.05 = 0.031999999999999855
    assertTrue(triggered);
  }

  function test_shouldTrigger_withDefaultSmoothingFactor_EMAShouldEqualMedian() public {
    address rateFeed = rateFeedIDs[0];

    uint256[5] memory medians;
    medians[0] = 0.997 * 10**24;
    medians[1] = 0.9968 * 10**24;
    medians[2] = 0.9769 * 10**24;
    medians[3] = 0.9759 * 10**24;
    medians[4] = 0.9854 * 10**24;

    for (uint256 i = 0; i < medians.length; i++) {
      setSortedOraclesMedian(medians[i]);
      breaker.shouldTrigger(rateFeed);
      assertEq(breaker.medianRatesEMA(rateFeed), medians[i]);
    }
  }

  function test_shouldTrigger_withLongSequencesOfUpdates_shouldCalculateEMACorrectly() public {
    address rateFeed = rateFeedIDs[0];
    uint256 smoothingFactor = 0.1 * 10**24;
    breaker.setSmoothingFactor(rateFeed, smoothingFactor);

    uint256[5] memory medians;
    medians[0] = 0.997 * 10**24;
    medians[1] = 0.9968 * 10**24;
    medians[2] = 0.9769 * 10**24;
    medians[3] = 0.9759 * 10**24;
    medians[4] = 0.9854 * 10**24;

    uint256[5] memory expectedEMAs;
    expectedEMAs[0] = 0.997 * 10**24;
    expectedEMAs[1] = 0.99698 * 10**24;
    expectedEMAs[2] = 0.994972 * 10**24;
    expectedEMAs[3] = 0.9930648 * 10**24;
    expectedEMAs[4] = 0.99229832 * 10**24;

    for (uint256 i = 0; i < medians.length; i++) {
      setSortedOraclesMedian(medians[i]);
      breaker.shouldTrigger(rateFeed);
      assertEq(breaker.medianRatesEMA(rateFeed), expectedEMAs[i]);
    }
  }
}
