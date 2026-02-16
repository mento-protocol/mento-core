// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, private-vars-leading-underscore
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";
import { MarketHoursBreaker } from "contracts/oracles/breakers/MarketHoursBreaker.sol";

// solhint-disable-next-line max-line-length
import { BokkyPooBahsDateTimeLibrary as DateTimeLibrary } from "BokkyPooBahsDateTimeLibrary/contracts/BokkyPooBahsDateTimeLibrary.sol";

contract MarketHoursBreakerTest is Test {
  IMarketHoursBreaker breaker;

  function setUp() public virtual {
    breaker = IMarketHoursBreaker(address(new MarketHoursBreaker()));
  }

  function getOpenMarketHours() public pure returns (uint256[] memory) {
    uint256[] memory timestamps = new uint256[](12);

    timestamps[0] = DateTimeLibrary.timestampFromDateTime(2024, 8, 12, 9, 0, 0); // Monday 09:00
    timestamps[1] = DateTimeLibrary.timestampFromDateTime(2024, 8, 13, 15, 30, 0); // Tuesday 15:30
    timestamps[2] = DateTimeLibrary.timestampFromDateTime(2024, 8, 14, 12, 0, 0); // Wednesday 12:00
    timestamps[3] = DateTimeLibrary.timestampFromDateTime(2024, 8, 15, 18, 45, 0); // Thursday 18:45
    timestamps[4] = DateTimeLibrary.timestampFromDateTime(2024, 8, 9, 20, 59, 0); // Friday 20:59
    timestamps[5] = DateTimeLibrary.timestampFromDateTime(2024, 8, 11, 23, 0, 0); // Sunday 23:00
    timestamps[6] = DateTimeLibrary.timestampFromDateTime(2025, 12, 24, 21, 59, 59); // Dec 24th before 22 UTC
    timestamps[7] = DateTimeLibrary.timestampFromDateTime(2025, 12, 26, 0, 0, 0); // Dec 26th
    timestamps[8] = DateTimeLibrary.timestampFromDateTime(2024, 2, 29, 18, 30, 0); // Feb 29th (Thurs)
    timestamps[9] = DateTimeLibrary.timestampFromDateTime(2024, 3, 1, 20, 59, 0); // Mar 1st (Fri)
    timestamps[10] = DateTimeLibrary.timestampFromDateTime(2024, 12, 31, 21, 59, 59); // Dec 31th before 22 UTC
    timestamps[11] = DateTimeLibrary.timestampFromDateTime(2025, 1, 2, 0, 0, 0); // Jan 2nd

    return timestamps;
  }

  function getClosedMarketHours() public pure returns (uint256[] memory) {
    uint256[] memory timestamps = new uint256[](8);

    timestamps[0] = DateTimeLibrary.timestampFromDateTime(2024, 8, 9, 21, 0, 0); // Friday 21:00
    timestamps[1] = DateTimeLibrary.timestampFromDateTime(2024, 8, 9, 23, 0, 0); // Friday 23:00
    timestamps[2] = DateTimeLibrary.timestampFromDateTime(2024, 8, 10, 0, 0, 0); // Saturday 00:00
    timestamps[3] = DateTimeLibrary.timestampFromDateTime(2024, 8, 10, 12, 0, 0); // Saturday 12:00
    timestamps[4] = DateTimeLibrary.timestampFromDateTime(2024, 8, 10, 23, 59, 0); // Saturday 23:59
    timestamps[5] = DateTimeLibrary.timestampFromDateTime(2024, 8, 11, 0, 0, 0); // Sunday 00:00
    timestamps[6] = DateTimeLibrary.timestampFromDateTime(2024, 8, 11, 12, 0, 0); // Sunday 12:00
    timestamps[7] = DateTimeLibrary.timestampFromDateTime(2024, 8, 11, 22, 59, 0); // Sunday 22:59

    return timestamps;
  }

  function getHolidays() public pure returns (uint256[] memory) {
    uint256[] memory timestamps = new uint256[](6);

    // Christmas Eve
    timestamps[0] = DateTimeLibrary.timestampFromDateTime(2025, 12, 24, 22, 0, 0);

    // Christmas
    timestamps[1] = DateTimeLibrary.timestampFromDateTime(2025, 12, 25, 0, 0, 0);
    timestamps[2] = DateTimeLibrary.timestampFromDateTime(2025, 12, 25, 23, 59, 59);

    // New Years Eve
    timestamps[3] = DateTimeLibrary.timestampFromDateTime(2025, 12, 31, 22, 0, 0);

    // New Years
    timestamps[4] = DateTimeLibrary.timestampFromDateTime(2026, 1, 1, 0, 0, 0);
    timestamps[5] = DateTimeLibrary.timestampFromDateTime(2026, 1, 1, 23, 59, 59);

    return timestamps;
  }
}

contract MarketHoursBreakerTest_shouldTrigger is MarketHoursBreakerTest {
  function test_shouldTrigger_whenInsideMarketHours_shouldReturnFalse() public {
    uint256[] memory ts = getOpenMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      vm.warp(ts[i]);
      assertFalse(breaker.shouldTrigger(address(0)));
    }
  }

  function test_shouldTrigger_whenOutsideOfMarketHours_shouldRevert() public {
    uint256[] memory ts = getClosedMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      vm.warp(ts[i]);

      vm.expectRevert("MarketHoursBreaker: FX market is closed");
      breaker.shouldTrigger(address(0));
    }
  }

  function test_shouldTrigger_whenOnHolidays_shouldRevert() public {
    uint256[] memory ts = getHolidays();

    for (uint256 i = 0; i < ts.length; i++) {
      vm.warp(ts[i]);

      vm.expectRevert("MarketHoursBreaker: FX market is closed");
      breaker.shouldTrigger(address(0));
    }
  }
}

contract MarketHoursBreakerTest_isFXMarketOpen is MarketHoursBreakerTest {
  function test_isFXMarketOpen_returnsTrueDuringBusinessHours() public view {
    uint256[] memory ts = getOpenMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      assertTrue(breaker.isFXMarketOpen(ts[i]));
    }
  }

  function test_isFXMarketOpen_returnsFalseDuringWeekends() public view {
    uint256[] memory ts = getClosedMarketHours();

    for (uint256 i = 0; i < ts.length; i++) {
      assertFalse(breaker.isFXMarketOpen(ts[i]));
    }
  }

  function test_isFXMarketOpen_returnsFalseDuringHolidays() public view {
    uint256[] memory ts = getHolidays();

    for (uint256 i = 0; i < ts.length; i++) {
      assertFalse(breaker.isFXMarketOpen(ts[i]));
    }
  }
}
