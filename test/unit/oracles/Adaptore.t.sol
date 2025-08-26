// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { Adaptore } from "contracts/oracles/Adaptore.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";

contract AdaptoreTest is Test {
  IAdaptore adaptore;

  address public sortedOracles = makeAddr("SortedOracles");
  address public breakerBox = makeAddr("BreakerBox");
  address public marketHoursBreaker = makeAddr("MarketHoursBreaker");
  address public referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");
  uint256 public blockTs = 1756170702;

  function setUp() public {
    adaptore = new Adaptore(sortedOracles, breakerBox, marketHoursBreaker);
  }

  function test_sortedOracles_shouldReturnSortedOracles() public {
    assertEq(address(adaptore.sortedOracles()), sortedOracles);
  }

  function test_breakerBox_shouldReturnBreakerBox() public {
    assertEq(address(adaptore.breakerBox()), breakerBox);
  }

  function test_marketHoursBreaker_shouldReturnMarketHoursBreaker() public {
    assertEq(address(adaptore.marketHoursBreaker()), marketHoursBreaker);
  }

  function test_getRate_returnsRateWith18DecimalsPrecision() public withOracleRate(1e20, 1e18) {
    (uint256 numerator, uint256 denominator) = adaptore.getRate(referenceRateFeedID);

    assertEq(numerator, 1e14);
    assertEq(denominator, 1e12);
  }

  function test_getTradingMode_returnsModeFromBreakerBox() public withTradingMode(1) {
    assertEq(adaptore.getTradingMode(referenceRateFeedID), 1);
  }

  function test_isMarketOpen_returnsTrueIfMarketIsOpen() public withMarketOpen(true) {
    assertTrue(adaptore.isMarketOpen());
  }

  function test_isMarketOpen_returnsFalseIfMarketIsClosed() public withMarketOpen(false) {
    assertFalse(adaptore.isMarketOpen());
  }

  function test_hasValidRate_returnsFalseAfterExpiryTimeFromPastRate()
    public
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 6 minutes + 2 seconds)
  {
    vm.warp(blockTs);

    assertTrue(adaptore.hasValidRate(referenceRateFeedID));

    skip(1);
    assertTrue(adaptore.hasValidRate(referenceRateFeedID));

    skip(1);
    assertFalse(adaptore.hasValidRate(referenceRateFeedID));
  }

  function test_hasValidRate_returnsFalseAfterReportExpiryTimeFromCurrentRate()
    public
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs)
  {
    vm.warp(blockTs + 6 minutes - 1 seconds);
    assertTrue(adaptore.hasValidRate(referenceRateFeedID));

    skip(1);

    assertFalse(adaptore.hasValidRate(referenceRateFeedID));

    skip(1 minutes);

    assertFalse(adaptore.hasValidRate(referenceRateFeedID));
  }

  modifier withMarketOpen(bool isMarketOpen) {
    bytes memory isMarketOpenCalldata = abi.encodeWithSelector(
      IMarketHoursBreaker.isMarketOpen.selector,
      block.timestamp
    );
    vm.mockCall(marketHoursBreaker, isMarketOpenCalldata, abi.encode(isMarketOpen));

    _;
  }

  modifier withOracleRate(uint256 nominator, uint256 denominator) {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(nominator, denominator));

    _;
  }

  modifier withReportExpiry(uint256 expiry) {
    bytes memory expiryCalldata = abi.encodeWithSelector(
      ISortedOracles.getTokenReportExpirySeconds.selector,
      referenceRateFeedID
    );
    vm.mockCall(sortedOracles, expiryCalldata, abi.encode(expiry));

    _;
  }

  modifier withMedianTimestamp(uint256 timestamp) {
    bytes memory medianTimestampCalldata = abi.encodeWithSelector(
      ISortedOracles.medianTimestamp.selector,
      referenceRateFeedID
    );
    vm.mockCall(sortedOracles, medianTimestampCalldata, abi.encode(timestamp));

    _;
  }

  modifier withTradingMode(uint256 tradingMode) {
    bytes memory tradingModeCalldata = abi.encodeWithSelector(
      IBreakerBox.getRateFeedTradingMode.selector,
      referenceRateFeedID
    );
    vm.mockCall(breakerBox, tradingModeCalldata, abi.encode(tradingMode));

    _;
  }
}
