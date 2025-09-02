// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";
import { MarketHoursBreaker } from "contracts/oracles/breakers/MarketHoursBreaker.sol";
import { BokkyPooBahsDateTimeLibrary } from "BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";

contract MarketHoursBreakerTest is Test {
  IMarketHoursBreaker breaker;

  uint256 defaultCooldownTime = 7 minutes;

  address notDeployer;
  address rateFeedID1;
  address rateFeedID2;
  address rateFeedID3;

  address[] rateFeedIDs;
  uint256[] cooldownTimes;

  event DefaultCooldownTimeUpdated(uint256 newCooldownTime);
  event RateFeedCooldownTimeUpdated(address rateFeedID, uint256 newCooldownTime);

  function setUp() public virtual {
    notDeployer = makeAddr("notDeployer");
    rateFeedID1 = makeAddr("rateFeedID1");
    rateFeedID2 = makeAddr("rateFeedID2");
    rateFeedID3 = makeAddr("rateFeedID3");

    rateFeedIDs = new address[](2);
    rateFeedIDs[0] = rateFeedID1;
    rateFeedIDs[1] = rateFeedID2;

    cooldownTimes = new uint256[](2);
    cooldownTimes[0] = 10 minutes;
    cooldownTimes[1] = 20 minutes;

    breaker = IMarketHoursBreaker(address(new MarketHoursBreaker(defaultCooldownTime, rateFeedIDs, cooldownTimes)));
  }

  function getOpenMarketHours() public view returns (uint256[] memory) {
    uint256[] memory timestamps = new uint256[](10);

    timestamps[0] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 12, 9, 0, 0); // Monday 09:00
    timestamps[1] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 13, 15, 30, 0); // Tuesday 15:30
    timestamps[2] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 14, 12, 0, 0); // Wednesday 12:00
    timestamps[3] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 15, 18, 45, 0); // Thursday 18:45
    timestamps[4] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 9, 20, 59, 0); // Friday 20:59
    timestamps[5] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 11, 23, 0, 0); // Sunday 23:00
    timestamps[6] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 12, 24, 23, 59, 59); // Dec 24th
    timestamps[7] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 12, 26, 0, 0, 0); // Dec 26th
    timestamps[8] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 2, 29, 18, 30, 0); // Feb 29th (Thurs)
    timestamps[9] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 3, 1, 20, 59, 0); // Mar 1st (Fri)

    return timestamps;
  }

  function getClosedMarketHours() public view returns (uint256[] memory) {
    uint256[] memory timestamps = new uint256[](8);

    timestamps[0] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 9, 21, 0, 0); // Friday 21:00
    timestamps[1] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 9, 23, 0, 0); // Friday 23:00
    timestamps[2] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 10, 0, 0, 0); // Saturday 00:00
    timestamps[3] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 10, 12, 0, 0); // Saturday 12:00
    timestamps[4] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 10, 23, 59, 0); // Saturday 23:59
    timestamps[5] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 11, 0, 0, 0); // Sunday 00:00
    timestamps[6] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 11, 12, 0, 0); // Sunday 12:00
    timestamps[7] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 8, 11, 22, 59, 0); // Sunday 21:59

    return timestamps;
  }

  function getHolidays() public view returns (uint256[] memory) {
    uint256[] memory timestamps = new uint256[](4);

    // Christmas
    timestamps[0] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 12, 25, 0, 0, 0);
    timestamps[1] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 12, 25, 23, 59, 59);

    // New Years
    timestamps[2] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 1, 1, 0, 0, 0);
    timestamps[3] = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(2024, 1, 1, 23, 59, 59);

    return timestamps;
  }
}

contract MarketHoursBreakerTest_constructorSettersAndGetters is MarketHoursBreakerTest {
  /* ---------- Constructor ---------- */

  function test_constructor_shouldSetOwner() public view {
    assertEq(breaker.owner(), address(this));
  }

  function test_constructor_shouldSetDefaultCooldownTime() public view {
    assertEq(breaker.defaultCooldownTime(), defaultCooldownTime);
  }

  function test_constructor_shouldSetRateFeedCooldownTimes() public view {
    assertEq(breaker.getCooldown(rateFeedIDs[0]), cooldownTimes[0]);
    assertEq(breaker.getCooldown(rateFeedIDs[1]), cooldownTimes[1]);
  }

  function test_constructor_withEmptyArrays_shouldSetDefaultCooldown() public {
    address[] memory emptyRateFeedIDs = new address[](0);
    uint256[] memory emptyCooldownTimes = new uint256[](0);

    MarketHoursBreaker newBreaker = new MarketHoursBreaker(defaultCooldownTime, emptyRateFeedIDs, emptyCooldownTimes);

    assertEq(newBreaker.defaultCooldownTime(), defaultCooldownTime);
    assertEq(newBreaker.getCooldown(rateFeedIDs[0]), defaultCooldownTime);
    assertEq(newBreaker.getCooldown(rateFeedIDs[1]), defaultCooldownTime);
  }

  /* ---------- Setters ---------- */

  function test_setDefaultCooldownTime_whenCallerIsNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(notDeployer);
    breaker.setDefaultCooldownTime(2 minutes);
  }

  function test_setDefaultCooldownTime_whenCallerIsOwner_shouldUpdateAndEmit() public {
    uint256 testCooldown = 39 minutes;
    vm.expectEmit(false, false, false, true);
    emit DefaultCooldownTimeUpdated(testCooldown);

    breaker.setDefaultCooldownTime(testCooldown);

    assertEq(breaker.defaultCooldownTime(), testCooldown);
  }

  function test_setCooldownTimes_whenCallerIsNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(notDeployer);
    breaker.setCooldownTimes(rateFeedIDs, cooldownTimes);
  }

  function test_setCooldownTimes_whenArraysAreDifferentLengths_shouldRevert() public {
    address[] memory rateFeedIDs2 = new address[](3);
    rateFeedIDs2[0] = rateFeedID1;
    rateFeedIDs2[1] = rateFeedID2;
    rateFeedIDs2[2] = rateFeedID3;

    vm.expectRevert("array length missmatch");
    breaker.setCooldownTimes(rateFeedIDs2, cooldownTimes);
  }

  function test_setCooldownTimes_whenRateFeedIDIsZero_shouldRevert() public {
    address[] memory rateFeedIDsWithZero = new address[](1);
    uint256[] memory cooldownTimesWithZero = new uint256[](1);
    rateFeedIDsWithZero[0] = address(0);
    cooldownTimesWithZero[0] = 5 minutes;

    vm.expectRevert("rate feed invalid");
    breaker.setCooldownTimes(rateFeedIDsWithZero, cooldownTimesWithZero);
  }

  function test_setCooldownTimes_whenCallerIsOwner_shouldUpdateAndEmit() public {
    address[] memory newRateFeedIDs = new address[](1);
    uint256[] memory newCooldownTimes = new uint256[](1);
    newRateFeedIDs[0] = rateFeedID3;
    newCooldownTimes[0] = 30 minutes;

    vm.expectEmit(true, true, true, true);
    emit RateFeedCooldownTimeUpdated(newRateFeedIDs[0], newCooldownTimes[0]);

    breaker.setCooldownTimes(newRateFeedIDs, newCooldownTimes);

    assertEq(breaker.getCooldown(newRateFeedIDs[0]), newCooldownTimes[0]);
  }

  /* ---------- Getters ---------- */

  function test_getCooldown_withDefault_shouldReturnDefaultCooldown() public view {
    assertEq(breaker.getCooldown(rateFeedID3), defaultCooldownTime);
  }

  function test_getCooldown_withSpecific_shouldReturnSpecificCooldown() public view {
    assertEq(breaker.getCooldown(rateFeedIDs[0]), cooldownTimes[0]);
    assertEq(breaker.getCooldown(rateFeedIDs[1]), cooldownTimes[1]);
  }
}

contract MarketHoursBreakerTest_shouldTrigger is MarketHoursBreakerTest {
  function test_shouldTrigger_returnsFalseInsideOfMarketHours() public {
    uint256[] memory ts = getOpenMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      vm.warp(ts[i]);
      assertFalse(breaker.shouldTrigger(address(0)));
    }
  }

  function test_shouldTrigger_returnsTrueOutsideOfMarketHours() public {
    uint256[] memory ts = getClosedMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      vm.warp(ts[i]);
      assertTrue(breaker.shouldTrigger(address(0)));
    }
  }

  function test_shouldTrigger_returnsTrueOnHolidays() public {
    uint256[] memory ts = getHolidays();

    for (uint256 i = 0; i < ts.length; i++) {
      vm.warp(ts[i]);
      assertTrue(breaker.shouldTrigger(address(0)));
    }
  }
}

contract MarketHoursBreakerTest_shouldReset is MarketHoursBreakerTest {
  function test_shouldReset_returnsOppositeOfShouldTrigger() public {
    uint256[] memory outsideMarketHours = getClosedMarketHours();

    for (uint256 i = 0; i < outsideMarketHours.length; i++) {
      vm.warp(outsideMarketHours[i]);
      assertTrue(breaker.shouldTrigger(address(0)));
      assertFalse(breaker.shouldReset(address(0)));
    }

    uint256[] memory holidays = getHolidays();

    for (uint256 i = 0; i < holidays.length; i++) {
      vm.warp(holidays[i]);
      assertTrue(breaker.shouldTrigger(address(0)));
      assertFalse(breaker.shouldReset(address(0)));
    }

    uint256[] memory insideMarketHours = getOpenMarketHours();

    for (uint256 i = 0; i < insideMarketHours.length; i++) {
      vm.warp(insideMarketHours[i]);
      assertFalse(breaker.shouldTrigger(address(0)));
      assertTrue(breaker.shouldReset(address(0)));
    }
  }
}

contract MarketHoursBreakerTest_isMarketOpen is MarketHoursBreakerTest {
  function test_isMarketOpen_returnsTrueDuringBusinessHours() public {
    uint256[] memory ts = getOpenMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      assertTrue(breaker.isMarketOpen(ts[i]));
    }
  }

  function test_isMarketOpen_returnsFalseDuringWeekends() public {
    uint256[] memory ts = getClosedMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      assertFalse(breaker.isMarketOpen(ts[i]));
    }
  }

  function test_isMarketOpen_returnsFalseDuringHolidays() public {
    uint256[] memory ts = getHolidays();

    for (uint256 i = 0; i < ts.length; i++) {
      assertFalse(breaker.isMarketOpen(ts[i]));
    }
  }
}
