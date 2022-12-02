// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { WithRegistry } from "./utils/WithRegistry.sol";
import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { SortedLinkedListWithMedian } from "contracts/common/linkedlists/SortedLinkedListWithMedian.sol";
import { MedianDeltaBreaker } from "contracts/MedianDeltaBreaker.sol";

import { MockSortedOracles } from "./mocks/MockSortedOracles.sol";

contract MedianDeltaBreakerTest is Test, WithRegistry {
  address deployer;
  address notDeployer;

  address rateFeedID;
  MockSortedOracles sortedOracles;
  MedianDeltaBreaker breaker;

  uint256 threshold = 0.15 * 10**24; // 15%
  uint256 coolDownTime = 5 minutes;

  address[] rateFeedIDs = new address[](2);
  uint256[] rateChangeThresholds = new uint256[](2);

  event BreakerTriggered(address indexed rateFeedID);
  event BreakerReset(address indexed rateFeedID);
  event CooldownTimeUpdated(uint256 newCooldownTime);
  event DefaultRateChangeThresholdUpdated(uint256 newMinRateChangeThreshold);
  event SortedOraclesUpdated(address newSortedOracles);
  event RateChangeThresholdUpdated(address rateFeedID, uint256 rateChangeThreshold);

  function setUp() public {
    deployer = actor("deployer");
    notDeployer = actor("notDeployer");
    rateFeedID = actor("rateFeedID");

    rateFeedIDs[0] = actor("rateFeedId0");
    rateFeedIDs[1] = actor("rateFeedId1");
    rateChangeThresholds[0] = 0.14 * 10**24;
    rateChangeThresholds[1] = 0.13 * 10**24;

    changePrank(deployer);
    sortedOracles = new MockSortedOracles();

    sortedOracles.addOracle(rateFeedIDs[0], actor("oracleClient"));
    sortedOracles.addOracle(rateFeedIDs[1], actor("oracleClient1"));

    breaker = new MedianDeltaBreaker(
      coolDownTime,
      threshold,
      rateFeedIDs,
      rateChangeThresholds,
      ISortedOracles(address(sortedOracles))
    );
  }

  function setupSortedOracles(uint256 currentMedianRate, uint256 previousMedianRate) public {
    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(sortedOracles.previousMedianRate.selector),
      abi.encode(previousMedianRate)
    );

    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(sortedOracles.medianRate.selector),
      abi.encode(currentMedianRate, 1)
    );
  }
}

contract MedianDeltaBreakerTest_constructorAndSetters is MedianDeltaBreakerTest {
  /* ---------- Constructor ---------- */

  function test_constructor_shouldSetOwner() public {
    assertEq(breaker.owner(), deployer);
  }

  function test_constructor_shouldSetCooldownTime() public {
    assertEq(breaker.cooldownTime(), coolDownTime);
  }

  function test_constructor_shouldSetRateChangeThreshold() public {
    assertEq(breaker.defaultRateChangeThreshold(), threshold);
  }

  function test_constructor_shouldSetSortedOracles() public {
    assertEq(address(breaker.sortedOracles()), address(sortedOracles));
  }

  function test_constructor_shouldSetRateChangeThresholds() public {
    assertEq(breaker.rateChangeThreshold(rateFeedIDs[0]), rateChangeThresholds[0]);
    assertEq(breaker.rateChangeThreshold(rateFeedIDs[1]), rateChangeThresholds[1]);
  }

  /* ---------- Setters ---------- */

  function test_setCooldownTime_whenCallerIsNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(notDeployer);
    breaker.setCooldownTime(2 minutes);
  }

  function test_setCooldownTime_whenCallerIsOwner_shouldUpdateAndEmit() public {
    uint256 testCooldown = 39 minutes;
    vm.expectEmit(false, false, false, true);
    emit CooldownTimeUpdated(testCooldown);

    breaker.setCooldownTime(testCooldown);

    assertEq(breaker.cooldownTime(), testCooldown);
  }

  function test_setRateChangeThreshold_whenCallerIsNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(notDeployer);

    breaker.setDefaultRateChangeThreshold(123456);
  }

  function test_setRateChangeThreshold_whenValueGreaterThanOne_shouldRevert() public {
    vm.expectRevert("rate change threshold must be less than 1");
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
    address[] memory rateFeedIDs2 = new address[](1);
    rateFeedIDs2[0] = actor("randomRateFeed");
    vm.expectRevert("rate feeds and rate change thresholds have to be the same length");
    breaker.setRateChangeThresholds(rateFeedIDs2, rateChangeThresholds);
  }

  function test_setRateChangeThreshold_whenThresholdIsMoreThan0_shouldRevert() public {
    rateChangeThresholds[0] = 1 * 10**24;
    vm.expectRevert("rate change threshold must be less than 1");
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
  }

  function test_setRateChangeThreshold_whenRateFeedIdDoesNotExist_shouldRevert() public {
    rateFeedIDs[0] = actor("randomRateFeed");
    vm.expectRevert("rate feed ID does not exist as it has 0 oracles");
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
  }

  function test_setRateChangeThreshold_whenSenderIsOwner_shouldUpdateAndEmit() public {
    vm.expectEmit(true, true, true, true);
    emit RateChangeThresholdUpdated(rateFeedIDs[0], rateChangeThresholds[0]);
    vm.expectEmit(true, true, true, true);
    emit RateChangeThresholdUpdated(rateFeedIDs[1], rateChangeThresholds[1]);
    breaker.setRateChangeThresholds(rateFeedIDs, rateChangeThresholds);
    assertEq(breaker.rateChangeThreshold(rateFeedIDs[0]), rateChangeThresholds[0]);
    assertEq(breaker.rateChangeThreshold(rateFeedIDs[1]), rateChangeThresholds[1]);
  }

  /* ---------- Getters ---------- */
  function test_getCooldown_shouldReturnCooldown() public {
    assertEq(breaker.getCooldown(), coolDownTime);
  }
}

contract MedianDeltaBreakerTest_shouldTrigger is MedianDeltaBreakerTest {
  function updateMedianByPercent(uint256 medianChangeScaleFactor, address _rateFeedID) public {
    uint256 previousMedianRate = 0.98 * 10**24;
    uint256 currentMedianRate = (previousMedianRate * medianChangeScaleFactor) / 10**24;
    setupSortedOracles(currentMedianRate, previousMedianRate);

    vm.expectCall(
      address(sortedOracles),
      abi.encodeWithSelector(sortedOracles.previousMedianRate.selector, _rateFeedID)
    );
    vm.expectCall(address(sortedOracles), abi.encodeWithSelector(sortedOracles.medianRate.selector, _rateFeedID));
  }

  function test_shouldTrigger_whenMedianDrops30Percent_shouldReturnTrue() public {
    // rateChangeThreshold not configured
    updateMedianByPercent(0.7 * 10**24, rateFeedID);
    assertTrue(breaker.shouldTrigger(rateFeedID));

    // rateChangeThreshold 14 %
    updateMedianByPercent(0.7 * 10**24, rateFeedIDs[0]);
    assertTrue(breaker.shouldTrigger(rateFeedIDs[0]));
  }

  function test_shouldTrigger_whenMedianDrops10Percent_shouldReturnFalse() public {
    // rateChangeThreshold not configured
    updateMedianByPercent(0.9 * 10**24, rateFeedID);
    assertFalse(breaker.shouldTrigger(rateFeedID));

    // rateChangeThreshold 14 %
    updateMedianByPercent(0.9 * 10**24, rateFeedIDs[0]);
    assertFalse(breaker.shouldTrigger(rateFeedIDs[0]));
  }

  function test_shouldTrigger_whenMedianIncreases10Percent_shouldReturnFalse() public {
    // rateChangeThreshold not configured
    updateMedianByPercent(1.1 * 10**24, rateFeedID);
    assertFalse(breaker.shouldTrigger(rateFeedID));

    // rateChangeThreshold 13 %
    updateMedianByPercent(1.1 * 10**24, rateFeedIDs[1]);
    assertFalse(breaker.shouldTrigger(rateFeedIDs[1]));
  }

  function test_shouldTrigger_whenMedianIncreases20Percent_shouldReturnTrue() public {
    // rateChangeThreshold not configured
    updateMedianByPercent(1.2 * 10**24, rateFeedID);
    assertTrue(breaker.shouldTrigger(rateFeedID));

    // rateChangeThreshold 13 %
    updateMedianByPercent(1.2 * 10**24, rateFeedIDs[1]);
    assertTrue(breaker.shouldTrigger(rateFeedIDs[1]));
  }
}
