// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { OneToOneFPMMBaseTest } from "./OneToOneFPMMBaseTest.sol";

contract OneToOneFPMMGetAmountOutTest is OneToOneFPMMBaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_getAmountOut_whenAmountIsZero_shouldReturnZero() public initializeFPMM_withDecimalTokens(18, 18) {
    assertEq(fpmm.getAmountOut(0, token0), 0);
  }

  function test_getAmountOut_whenTokenIsInvalid_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    address invalidToken = makeAddr("INVALID_TOKEN");

    vm.expectRevert("FPMM: INVALID_TOKEN");
    fpmm.getAmountOut(100, invalidToken);
  }

  function test_getAmountOut_whenRateIsAlways1to1_shouldReturnCorrectAmount()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);

    // Even though oracle says 2:1, OneToOneFPMM always returns 1:1 (minus fee)
    uint256 expectedAmountOut = 99.7e18; // 100e18 - 0.3% fee
    assertEq(amountOut, expectedAmountOut);

    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenLPFeeChanges_shouldRespectLPFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(10e18, 100e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;

    // Change fee to 1%
    vm.prank(owner);
    fpmm.setLPFee(100); // 100 basis points = 1%
    // Still 1:1 rate, but with 1% fee instead of 0.3%
    uint256 expectedAmountOut = 99e18; // 100e18 - 1% fee
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);

    // Change fee to 0%
    vm.prank(owner);
    fpmm.setLPFee(0);
    expectedAmountOut = 100e18; // No fee, pure 1:1
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);
  }

  function test_getAmountOut_whenTokensHaveDifferentDecimals_shouldHandleConversionAt1to1()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    withOracleRate(2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // token0 (18 decimals) to token1 (6 decimals)
    // Even with oracle at 2:1, should be 1:1
    uint256 amountIn = 100e18; // 100 tokens with 18 decimals
    uint256 expectedAmountOut = 99.7e6; // 100 tokens with 6 decimals, minus 0.3% fee (1:1 rate)
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);

    // token1 (6 decimals) to token0 (18 decimals)
    amountIn = 100e6; // 100 tokens with 6 decimals
    expectedAmountOut = 99.7e18; // 100 tokens with 18 decimals, minus 0.3% fee (1:1 rate)
    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenProtocolFeeSet_shouldAccountForBothFees()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withProtocolFee(20, protocolFeeRecipient)
    withOracleRate(2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;

    // 1:1 rate, 0.3% LP fee + 0.2% protocol fee = 0.5% total
    uint256 expectedAmountOut = 99.5e18; // 100e18 - 0.5% total fees
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenLargeAmounts_shouldMaintain1to1Ratio()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(5e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 1_000_000e18; // 1 million tokens

    // Even with large amounts and oracle at 5:1, should be 1:1
    uint256 expectedAmountOut = 997_000e18; // 1M - 0.3% fee
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenTradingIsSuspended_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withTradingMode(TRADING_MODE_DISABLED)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    vm.expectRevert("OracleAdapter: TRADING_SUSPENDED");
    fpmm.getAmountOut(100e18, token0);
  }

  function test_getAmountOut_whenMarketIsClosed_shouldStillWork()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(false)
    withRecentRate(true)
  {
    // OneToOneFPMM is for stablecoin swaps (USD.m <-> USDC/USDT)
    // These should work even when FX markets are closed
    uint256 amountIn = 100e18;
    uint256 expectedAmountOut = 99.7e18; // 1:1 rate minus 0.3% fee

    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenRateIsExpired_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(false)
  {
    // OneToOneFPMM checks rate freshness via ensureRateValid
    vm.expectRevert("OracleAdapter: NO_RECENT_RATE");
    fpmm.getAmountOut(100e18, token0);
  }
}
