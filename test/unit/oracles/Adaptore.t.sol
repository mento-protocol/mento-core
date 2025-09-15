// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, private-vars-leading-underscore
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { Adaptore } from "contracts/oracles/Adaptore.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";
import { IAdaptore } from "contracts/interfaces/IAdaptore.sol";

contract AdaptoreTest is Test {
  Adaptore adaptore;

  address public sortedOracles = makeAddr("SortedOracles");
  address public breakerBox = makeAddr("BreakerBox");
  address public marketHoursBreaker = makeAddr("MarketHoursBreaker");
  address public referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");
  address public owner = makeAddr("OWNER");

  uint256 public blockTs = 1756170702;

  function setUp() public {
    adaptore = new Adaptore(false);
  }

  function test_initialize_shouldSetAllContracts() public {
    vm.prank(owner);
    adaptore.initialize(sortedOracles, breakerBox, marketHoursBreaker);

    assertEq(address(adaptore.sortedOracles()), sortedOracles);
    assertEq(address(adaptore.breakerBox()), breakerBox);
    assertEq(address(adaptore.marketHoursBreaker()), marketHoursBreaker);
    assertEq(adaptore.owner(), owner);
  }

  function test_initialize_whenCalledTwice_shouldRevert() public initialized {
    vm.expectRevert("Initializable: contract is already initialized");
    adaptore.initialize(sortedOracles, breakerBox, marketHoursBreaker);
  }

  function test_sortedOracles_shouldReturnSortedOracles() public initialized {
    assertEq(address(adaptore.sortedOracles()), sortedOracles);
  }

  function test_breakerBox_shouldReturnBreakerBox() public initialized {
    assertEq(address(adaptore.breakerBox()), breakerBox);
  }

  function test_marketHoursBreaker_shouldReturnMarketHoursBreaker() public initialized {
    assertEq(address(adaptore.marketHoursBreaker()), marketHoursBreaker);
  }

  function test_setSortedOracles_whenCalledByOwner_shouldUpdateAddress() public initialized {
    address newOracles = makeAddr("newOracles");

    vm.prank(owner);
    adaptore.setSortedOracles(newOracles);

    assertEq(address(adaptore.sortedOracles()), newOracles);
  }

  function test_setSortedOracles_whenCalledByNotOwner_shouldRevert() public initialized {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("NOT_OWNER"));
    adaptore.setSortedOracles(sortedOracles);
  }

  function test_setBreakerBox_whenCalledByOwner_shouldUpdateAddress() public initialized {
    address newBreakerBox = makeAddr("newBreakerBox");

    vm.prank(owner);
    adaptore.setBreakerBox(newBreakerBox);

    assertEq(address(adaptore.breakerBox()), newBreakerBox);
  }

  function test_setBreakerBox_whenCalledByNotOwner_shouldRevert() public initialized {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("NOT_OWNER"));
    adaptore.setBreakerBox(breakerBox);
  }

  function test_setMarketHoursBreaker_whenCalledByOwner_shouldUpdateAddress() public initialized {
    address newMarketHoursBreaker = makeAddr("newMarketHoursBreaker");

    vm.prank(owner);
    adaptore.setMarketHoursBreaker(newMarketHoursBreaker);

    assertEq(address(adaptore.marketHoursBreaker()), newMarketHoursBreaker);
  }

  function test_setMarketHoursBreaker_whenCalledByNotOwner_shouldRevert() public initialized {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("NOT_OWNER"));
    adaptore.setMarketHoursBreaker(marketHoursBreaker);
  }

  function test_getRateIfValid_whenMarketIsClosed_shouldRevert() public initialized withMarketOpen(false) {
    vm.expectRevert("Adaptore: MARKET_CLOSED");
    adaptore.getRateIfValid(referenceRateFeedID);
  }

  function test_getRateIfValid_whenTradingIsSuspended_shouldRevert()
    public
    initialized
    withMarketOpen(true)
    withTradingMode(1)
  {
    vm.expectRevert("Adaptore: TRADING_SUSPENDED");
    adaptore.getRateIfValid(referenceRateFeedID);
  }

  function test_getRateIfValid_whenNoRecentRate_shouldRevert()
    public
    initialized
    withOracleRate(1e20, 1e18)
    withMarketOpen(true)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 6 minutes + 1 seconds)
  {
    vm.warp(blockTs);

    adaptore.getRateIfValid(referenceRateFeedID);

    skip(1);

    vm.expectRevert("Adaptore: NO_RECENT_RATE");
    adaptore.getRateIfValid(referenceRateFeedID);
  }

  function test_getRate_returnsCorrectRateInfo_whenAllChecksValid()
    public
    initialized
    withOracleRate(1e20, 1e18)
    withMarketOpen(true)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 5 minutes)
  {
    vm.warp(blockTs);

    IAdaptore.RateInfo memory rateInfo = adaptore.getRate(referenceRateFeedID);

    assertEq(rateInfo.numerator, 1e14);
    assertEq(rateInfo.denominator, 1e12);
    assertEq(rateInfo.tradingMode, 0);
    assertEq(rateInfo.isRecent, true);
    assertEq(rateInfo.isMarketOpen, true);
  }

  function test_getRate_returnsCorrectRateInfo_whenSomeChecksInvalid()
    public
    initialized
    withOracleRate(1e20, 1e18)
    withMarketOpen(false)
    withTradingMode(1)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 7 minutes)
  {
    vm.warp(blockTs);

    IAdaptore.RateInfo memory rateInfo = adaptore.getRate(referenceRateFeedID);
    assertEq(rateInfo.numerator, 1e14);
    assertEq(rateInfo.denominator, 1e12);
    assertEq(rateInfo.tradingMode, 1);
    assertEq(rateInfo.isRecent, false);
    assertEq(rateInfo.isMarketOpen, false);
  }

  function test_getTradingMode_returnsModeFromBreakerBox() public initialized withTradingMode(1) {
    assertEq(adaptore.getTradingMode(referenceRateFeedID), 1);
  }

  function test_isMarketOpen_returnsTrueIfMarketIsOpen() public initialized withMarketOpen(true) {
    assertTrue(adaptore.isMarketOpen());
  }

  function test_isMarketOpen_returnsFalseIfMarketIsClosed() public initialized withMarketOpen(false) {
    assertFalse(adaptore.isMarketOpen());
  }

  function test_hasRecentRate_returnsFalseAfterExpiryTimeFromPastRate()
    public
    initialized
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 6 minutes + 2 seconds)
  {
    vm.warp(blockTs);

    assertTrue(adaptore.hasRecentRate(referenceRateFeedID));

    skip(1);
    assertTrue(adaptore.hasRecentRate(referenceRateFeedID));

    skip(1);
    assertFalse(adaptore.hasRecentRate(referenceRateFeedID));
  }

  function test_hasRecentRate_returnsFalseAfterReportExpiryTimeFromCurrentRate()
    public
    initialized
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs)
  {
    vm.warp(blockTs + 6 minutes - 1 seconds);
    assertTrue(adaptore.hasRecentRate(referenceRateFeedID));

    skip(1);
    assertFalse(adaptore.hasRecentRate(referenceRateFeedID));

    skip(1 minutes);
    assertFalse(adaptore.hasRecentRate(referenceRateFeedID));
  }

  modifier initialized() {
    vm.prank(owner);
    adaptore.initialize(sortedOracles, breakerBox, marketHoursBreaker);

    _;
  }

  modifier withMarketOpen(bool isMarketOpen) {
    bytes memory isMarketOpenCalldata = abi.encodeWithSelector(IMarketHoursBreaker.isMarketOpen.selector);
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
