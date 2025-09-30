// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";

contract FPMMGetAmountOutTest is FPMMBaseTest {
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

  function test_getAmountOut_whenRateIsOneToOne_shouldReturnCorrectAmount()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);

    uint256 expectedAmountOut = 99.7e18; // 100e18 - 0.3% fee
    assertEq(amountOut, expectedAmountOut);

    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenProtocolFeeChanges_shouldRespectProtocolFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(10e18, 100e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;

    // Change fee to 1%
    vm.prank(owner);
    fpmm.setProtocolFee(100); // 100 basis points = 1%
    uint256 expectedAmountOut = 9.9e18; // 10e18 - 1% fee
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);

    // Change fee to 0%
    vm.prank(owner);
    fpmm.setProtocolFee(0);
    expectedAmountOut = 10e18; // No fee
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);
  }

  function test_getAmountOut_whenUsingExchangeRate_shouldConvertCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;

    // token0 to token1: should get approximately double (minus fee)
    uint256 expectedAmountOut = 199.4e18; // (100e18 - 0.3% fee) * 2
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);

    // token1 to token0: should get approximately half (minus fee)
    expectedAmountOut = 49.85e18; // (100e18 - 0.3% fee) / 2
    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenTokensHaveDifferentDecimals_shouldHandleConversion()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // token0 (18 decimals) to token1 (6 decimals)
    uint256 amountIn = 100e18; // 100 tokens with 18 decimals
    uint256 expectedAmountOut = 99.7e6; // 100 tokens with 6 decimals, minus 0.3% fee
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);

    // token1 (6 decimals) to token0 (18 decimals)
    amountIn = 100e6; // 100 tokens with 6 decimals
    expectedAmountOut = 99.7e18; // 100 tokens with 18 decimals, minus 0.3% fee
    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenTokensHaveDifferentDecimalsAndExchangeRate_shouldConvertCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    withOracleRate(10e18, 100e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // token0 (18 decimals) to token1 (6 decimals)
    uint256 amountIn = 100e18; // 100 tokens with 18 decimals
    uint256 expectedAmountOut = 9.97e6; // (100 tokens - 0.3% fee) * 2, with 6 decimals
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);

    // token1 (6 decimals) to token0 (18 decimals)
    amountIn = 100e6; // 100 tokens with 6 decimals
    expectedAmountOut = 997e18; // (100 tokens - 0.3% fee) / 2, with 18 decimals
    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenUsingComplexRates_shouldCalculateCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1234e18, 5678e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 1000e18;

    // token0 to token1
    uint256 amountOutToken0 = fpmm.getAmountOut(amountIn, token0);
    uint256 expectedAmountOutToken0 = 216678055653399084184; // (1000e18 * 1234e18 / 5678e18) * (997 / 1000)
    assertEq(amountOutToken0, expectedAmountOutToken0);

    // token1 to token0
    uint256 amountOutToken1 = fpmm.getAmountOut(amountIn, token1);
    uint256 expectedAmountOutToken1 = 4587492706645056726094; // (1000e18 *  1234e18 / 5678e18) * (997 / 1000)
    assertEq(amountOutToken1, expectedAmountOutToken1);
  }

  function test_getAmountOut_whenMarketIsClosed_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(false)
    withRecentRate(true)
  {
    vm.expectRevert("OracleAdapter: FX_MARKET_CLOSED");
    fpmm.getAmountOut(100e18, token0);
  }

  function test_getAmountOut_whenRateIsExpired_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(false)
  {
    vm.expectRevert("OracleAdapter: NO_RECENT_RATE");
    fpmm.getAmountOut(100e18, token0);
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
}
