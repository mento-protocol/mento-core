// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, private-vars-leading-underscore
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";

import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";

contract OracleAdapterTest is Test {
  OracleAdapter oracleAdapter;

  address public sortedOracles = makeAddr("SortedOracles");
  address public breakerBox = makeAddr("BreakerBox");
  address public marketHoursBreaker = makeAddr("MarketHoursBreaker");
  address public referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");
  address public owner = makeAddr("OWNER");

  uint256 public blockTs = 1756170702;

  function setUp() public {
    oracleAdapter = new OracleAdapter(false);
  }

  function test_initialize_shouldSetAllContracts() public {
    oracleAdapter.initialize(sortedOracles, breakerBox, marketHoursBreaker, owner);

    assertEq(address(oracleAdapter.sortedOracles()), sortedOracles);
    assertEq(address(oracleAdapter.breakerBox()), breakerBox);
    assertEq(address(oracleAdapter.marketHoursBreaker()), marketHoursBreaker);
    assertEq(oracleAdapter.owner(), owner);
  }

  function test_initialize_whenCalledTwice_shouldRevert() public initialized {
    vm.expectRevert("Initializable: contract is already initialized");
    oracleAdapter.initialize(sortedOracles, breakerBox, marketHoursBreaker, owner);
  }

  function test_sortedOracles_shouldReturnSortedOracles() public initialized {
    assertEq(address(oracleAdapter.sortedOracles()), sortedOracles);
  }

  function test_breakerBox_shouldReturnBreakerBox() public initialized {
    assertEq(address(oracleAdapter.breakerBox()), breakerBox);
  }

  function test_marketHoursBreaker_shouldReturnMarketHoursBreaker() public initialized {
    assertEq(address(oracleAdapter.marketHoursBreaker()), marketHoursBreaker);
  }

  function test_setSortedOracles_whenCalledByOwner_shouldUpdateAddress() public initialized {
    address newOracles = makeAddr("newOracles");

    vm.prank(owner);
    oracleAdapter.setSortedOracles(newOracles);

    assertEq(address(oracleAdapter.sortedOracles()), newOracles);
  }

  function test_setSortedOracles_whenCalledWithZeroAddress_shouldRevert() public initialized {
    vm.prank(owner);
    vm.expectRevert(IOracleAdapter.ZeroAddress.selector);
    oracleAdapter.setSortedOracles(address(0));
  }

  function test_setSortedOracles_whenCalledByNotOwner_shouldRevert() public initialized {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("NOT_OWNER"));
    oracleAdapter.setSortedOracles(sortedOracles);
  }

  function test_setBreakerBox_whenCalledByOwner_shouldUpdateAddress() public initialized {
    address newBreakerBox = makeAddr("newBreakerBox");

    vm.prank(owner);
    oracleAdapter.setBreakerBox(newBreakerBox);

    assertEq(address(oracleAdapter.breakerBox()), newBreakerBox);
  }

  function test_setBreakerBox_whenCalledByNotOwner_shouldRevert() public initialized {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("NOT_OWNER"));
    oracleAdapter.setBreakerBox(breakerBox);
  }

  function test_setBreakerBox_whenCalledWithZeroAddress_shouldRevert() public initialized {
    vm.prank(owner);
    vm.expectRevert(IOracleAdapter.ZeroAddress.selector);
    oracleAdapter.setBreakerBox(address(0));
  }

  function test_setMarketHoursBreaker_whenCalledByOwner_shouldUpdateAddress() public initialized {
    address newMarketHoursBreaker = makeAddr("newMarketHoursBreaker");

    vm.prank(owner);
    oracleAdapter.setMarketHoursBreaker(newMarketHoursBreaker);

    assertEq(address(oracleAdapter.marketHoursBreaker()), newMarketHoursBreaker);
  }

  function test_setMarketHoursBreaker_whenCalledByNotOwner_shouldRevert() public initialized {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("NOT_OWNER"));
    oracleAdapter.setMarketHoursBreaker(marketHoursBreaker);
  }

  function test_setMarketHoursBreaker_whenCalledWithZeroAddress_shouldRevert() public initialized {
    vm.prank(owner);
    vm.expectRevert(IOracleAdapter.ZeroAddress.selector);
    oracleAdapter.setMarketHoursBreaker(address(0));
  }

  function test_getRateIfValid_whenTradingIsSuspended_shouldRevert()
    public
    initialized
    withFXMarketOpen(true)
    withTradingMode(1)
  {
    vm.expectRevert(IOracleAdapter.TradingSuspended.selector);
    oracleAdapter.getRateIfValid(referenceRateFeedID);
  }

  function test_getRateIfValid_whenValid_shouldNotRevert()
    public
    initialized
    withOracleRate(1e18, 1e18)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs)
  {
    vm.warp(blockTs);
    oracleAdapter.getRateIfValid(referenceRateFeedID);
  }

  function test_getRateIfValid_whenNoRecentRate_shouldRevert()
    public
    initialized
    withOracleRate(1e20, 1e18)
    withFXMarketOpen(true)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 6 minutes)
  {
    vm.warp(blockTs);

    oracleAdapter.getRateIfValid(referenceRateFeedID);

    skip(1);

    vm.expectRevert(IOracleAdapter.NoRecentRate.selector);
    oracleAdapter.getRateIfValid(referenceRateFeedID);
  }

  function test_getFXRateIfValid_whenFXMarketIsClosed_shouldRevert() public initialized withFXMarketOpen(false) {
    vm.expectRevert(IOracleAdapter.FXMarketClosed.selector);
    oracleAdapter.getFXRateIfValid(referenceRateFeedID);
  }

  function test_getFXRateIfValid_whenTradingIsSuspended_shouldRevert()
    public
    initialized
    withFXMarketOpen(true)
    withTradingMode(1)
  {
    vm.expectRevert(IOracleAdapter.TradingSuspended.selector);
    oracleAdapter.getFXRateIfValid(referenceRateFeedID);
  }

  function test_getFXRateIfValid_whenNoRecentRate_shouldRevert()
    public
    initialized
    withOracleRate(1e20, 1e18)
    withFXMarketOpen(true)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 6 minutes)
  {
    vm.warp(blockTs);

    oracleAdapter.getFXRateIfValid(referenceRateFeedID);

    skip(1);

    vm.expectRevert(IOracleAdapter.NoRecentRate.selector);
    oracleAdapter.getFXRateIfValid(referenceRateFeedID);
  }

  function test_getRate_returnsCorrectRateInfo_whenAllChecksValid()
    public
    initialized
    withOracleRate(1e20, 1e18)
    withFXMarketOpen(true)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 5 minutes)
  {
    vm.warp(blockTs);

    IOracleAdapter.RateInfo memory rateInfo = oracleAdapter.getRate(referenceRateFeedID);

    assertEq(rateInfo.numerator, 1e14);
    assertEq(rateInfo.denominator, 1e12);
    assertEq(rateInfo.tradingMode, 0);
    assertEq(rateInfo.isRecent, true);
    assertEq(rateInfo.isFXMarketOpen, true);
  }

  function test_getRate_returnsCorrectRateInfo_whenSomeChecksInvalid()
    public
    initialized
    withOracleRate(1e20, 1e18)
    withFXMarketOpen(false)
    withTradingMode(1)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 7 minutes)
  {
    vm.warp(blockTs);

    IOracleAdapter.RateInfo memory rateInfo = oracleAdapter.getRate(referenceRateFeedID);
    assertEq(rateInfo.numerator, 1e14);
    assertEq(rateInfo.denominator, 1e12);
    assertEq(rateInfo.tradingMode, 1);
    assertEq(rateInfo.isRecent, false);
    assertEq(rateInfo.isFXMarketOpen, false);
  }

  function test_getTradingMode_returnsModeFromBreakerBox() public initialized withTradingMode(1) {
    assertEq(oracleAdapter.getTradingMode(referenceRateFeedID), 1);
  }

  function test_ensureRateValid_whenTradingIsSuspended_shouldRevert()
    public
    initialized
    withTradingMode(3)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs)
  {
    vm.warp(blockTs);
    vm.expectRevert(IOracleAdapter.TradingSuspended.selector);
    oracleAdapter.ensureRateValid(referenceRateFeedID);
  }

  function test_ensureRateValid_whenNoRecentRate_shouldRevert()
    public
    initialized
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 7 minutes)
  {
    vm.warp(blockTs);
    vm.expectRevert(IOracleAdapter.NoRecentRate.selector);
    oracleAdapter.ensureRateValid(referenceRateFeedID);
  }

  function test_ensureRateValid_whenValid_shouldNotRevert()
    public
    initialized
    withOracleRate(1e18, 1e18)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs)
  {
    vm.warp(blockTs);
    oracleAdapter.ensureRateValid(referenceRateFeedID);
  }

  function test_ensureRateValid_whenRateIsZero_shouldRevert()
    public
    initialized
    withOracleRate(0, 0)
    withTradingMode(0)
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs)
  {
    vm.warp(blockTs);
    vm.expectRevert(IOracleAdapter.InvalidRate.selector);
    oracleAdapter.ensureRateValid(referenceRateFeedID);
  }

  function test_isFXMarketOpen_returnsTrueIfFXMarketIsOpen() public initialized withFXMarketOpen(true) {
    assertTrue(oracleAdapter.isFXMarketOpen());
  }

  function test_isFXMarketOpen_returnsFalseIfFXMarketIsClosed() public initialized withFXMarketOpen(false) {
    assertFalse(oracleAdapter.isFXMarketOpen());
  }

  function test_hasRecentRate_returnsFalseAfterExpiryTimeFromPastRate()
    public
    initialized
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs - 6 minutes + 1 seconds)
  {
    vm.warp(blockTs);
    assertTrue(oracleAdapter.hasRecentRate(referenceRateFeedID));

    skip(1);
    uint256 medianTs = ISortedOracles(sortedOracles).medianTimestamp(referenceRateFeedID);
    assertTrue(block.timestamp == medianTs + 6 minutes);
    assertTrue(oracleAdapter.hasRecentRate(referenceRateFeedID));

    skip(1);
    assertFalse(oracleAdapter.hasRecentRate(referenceRateFeedID));

    skip(1 minutes);
    assertFalse(oracleAdapter.hasRecentRate(referenceRateFeedID));
  }

  function test_hasRecentRate_returnsFalseAfterReportExpiryTimeFromCurrentRate()
    public
    initialized
    withReportExpiry(6 minutes)
    withMedianTimestamp(blockTs)
  {
    vm.warp(blockTs + 6 minutes - 1 seconds);
    assertTrue(oracleAdapter.hasRecentRate(referenceRateFeedID));

    skip(1);
    assertTrue(oracleAdapter.hasRecentRate(referenceRateFeedID));

    skip(1);
    assertFalse(oracleAdapter.hasRecentRate(referenceRateFeedID));

    skip(1 minutes);
    assertFalse(oracleAdapter.hasRecentRate(referenceRateFeedID));
  }

  modifier initialized() {
    oracleAdapter.initialize(sortedOracles, breakerBox, marketHoursBreaker, owner);

    _;
  }

  modifier withFXMarketOpen(bool isFXMarketOpen) {
    bytes memory isFXMarketOpenCalldata = abi.encodeWithSelector(IMarketHoursBreaker.isFXMarketOpen.selector);
    vm.mockCall(marketHoursBreaker, isFXMarketOpenCalldata, abi.encode(isFXMarketOpen));

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
