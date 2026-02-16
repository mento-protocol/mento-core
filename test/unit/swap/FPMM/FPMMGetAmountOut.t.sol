// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

contract FPMMGetAmountOutTest is FPMMBaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_getAmountOut_whenAmountIsZero_shouldReturnZero() public initializeFPMM_withDecimalTokens(18, 18) {
    assertEq(fpmm.getAmountOut(0, token0), 0);
  }

  function test_getAmountOut_whenTokenIsInvalid_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    address invalidToken = makeAddr("INVALID_TOKEN");

    vm.expectRevert(IFPMM.InvalidToken.selector);
    fpmm.getAmountOut(100, invalidToken);
  }

  function test_getAmountOut_whenRateIsOneToOne_shouldReturnCorrectAmount()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e24, 1e24)
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

  function test_getAmountOut_whenLPFeeChanges_shouldRespectLPFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e23, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;

    // Change fee to 1%
    vm.prank(owner);
    fpmm.setLPFee(100); // 100 basis points = 1%
    uint256 expectedAmountOut = 9.9e18; // 10e18 - 1% fee
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);

    // Change fee to 0%
    vm.prank(owner);
    fpmm.setLPFee(0);
    expectedAmountOut = 10e18; // No fee
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);
  }

  function test_getAmountOut_whenUsingExchangeRate_shouldConvertCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(6481420000000000000000, 1e24) // JPY/USD rate
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;

    // token0 to token1: should get approximately double (minus fee)
    uint256 expectedAmountOut = 646197574000000000; // 100e18 * 6481420000000000 / 1e18 * (997 / 1000)
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);

    // token1 to token0: should get approximately half (minus fee)
    expectedAmountOut = 15382431627637153586714; // // 100e18 * 1e18 / 6481420000000000 * (997 / 1000)
    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenTokensHaveDifferentDecimals_shouldHandleConversion()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    withOracleRate(1e24, 1e24)
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
    withOracleRate(1e23, 1e24)
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
    withOracleRate(7736000000000000000000, 1e24) // KES/USD rate
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 1000e18;

    // token0 to token1
    uint256 amountOutToken0 = fpmm.getAmountOut(amountIn, token0);
    uint256 expectedAmountOutToken0 = 7712792000000000000; // (1000e18 * 7736000000000000 / 1e18) * (997 / 1000)
    assertEq(amountOutToken0, expectedAmountOutToken0);

    // token1 to token0
    uint256 amountOutToken1 = fpmm.getAmountOut(amountIn, token1);
    uint256 expectedAmountOutToken1 = 128877973112719751809720; // (1000e18 * 1e18 / 7736000000000000) * (997 / 1000)
    assertEq(amountOutToken1, expectedAmountOutToken1);
  }

  function test_getAmountOut_whenProtocolFeeEnabled_shouldCalculateCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e24, 1e24)
    withProtocolFee(20, protocolFeeRecipient)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;
    uint256 expectedAmountOut = 99.5e18; // 100e18 - 0.3% lpFee - 0.2% protocolFee
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);
    assertEq(amountOut, expectedAmountOut);

    amountOut = fpmm.getAmountOut(amountIn, token1);
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_whenLPFeeDisabledAndProtocolFeeEnabled_shouldCalculateCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e24, 1e24)
    withProtocolFeeRecipient(protocolFeeRecipient)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    vm.prank(owner);
    fpmm.setLPFee(0);

    uint256 amountIn = 100e18;
    assertEq(fpmm.getAmountOut(amountIn, token0), amountIn); // No fee as of now

    vm.prank(owner);
    fpmm.setProtocolFee(200); // Max fee of 200bps / 2%

    assertEq(fpmm.getAmountOut(amountIn, token0), 98e18);
  }

  function test_getAmountOut_whenMarketIsClosed_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(false)
    withRecentRate(true)
  {
    vm.expectRevert(IOracleAdapter.FXMarketClosed.selector);
    fpmm.getAmountOut(100e18, token0);
  }

  function test_getAmountOut_whenRateIsExpired_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(false)
  {
    vm.expectRevert(IOracleAdapter.NoRecentRate.selector);
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
    vm.expectRevert(IOracleAdapter.TradingSuspended.selector);
    fpmm.getAmountOut(100e18, token0);
  }
}
