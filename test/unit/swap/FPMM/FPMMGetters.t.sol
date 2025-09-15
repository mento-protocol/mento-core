// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";

contract FPMMGettersTest is FPMMBaseTest {
  function test_getReserves_whenBeforeAnyMinting_shouldReturnZero() public initializeFPMM_withDecimalTokens(18, 18) {
    (uint256 reserve0, uint256 reserve1, ) = fpmm.getReserves();

    assertEq(reserve0, 0);
    assertEq(reserve1, 0);
  }

  function test_getReserves_whenAfterMinting_shouldReturnCorrectValues()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 amount0 = 100e18;
    uint256 amount1 = 200e18;

    (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast) = fpmm.getReserves();

    assertEq(reserve0, amount0);
    assertEq(reserve1, amount1);
    assertEq(blockTimestampLast, block.timestamp);
  }

  function test_metadata_whenPoolInitialized_shouldReturnCorrectValues()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
  {
    (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1) = fpmm.metadata();

    assertEq(dec0, 1e18);
    assertEq(dec1, 1e6);
    assertEq(r0, 100e18);
    assertEq(r1, 200e6);
    assertEq(t0, token0);
    assertEq(t1, token1);
  }

  function test_tokens_whenPoolInitialized_shouldReturnCorrectAddresses()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    (address t0, address t1) = fpmm.tokens();

    assertEq(t0, token0);
    assertEq(t1, token1);
  }

  function test_convertWithRate_whenSameDecimals_shouldConvertCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    uint256 amount = 100e18;
    uint256 numerator = 2e18; // 2:1 rate
    uint256 denominator = 1e18;

    uint256 convertedAmount = fpmm.convertWithRate(amount, 1e18, 1e18, numerator, denominator);

    assertEq(convertedAmount, 200e18); // 100 * 2 = 200
  }

  function test_convertWithRate_whenFromDecimalsLarger_shouldConvertCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 6)
  {
    uint256 amount = 100e18; // 100 of token0 (18 decimals)
    uint256 numerator = 2e18; // 2:1 rate
    uint256 denominator = 1e18;

    uint256 convertedAmount = fpmm.convertWithRate(amount, 1e18, 1e6, numerator, denominator);

    assertEq(convertedAmount, 200e6); // 100 * 2 / 10^12 = 200 * 10^6
  }

  function test_convertWithRate_whenFromDecimalsSmaller_shouldConvertCorrectly()
    public
    initializeFPMM_withDecimalTokens(6, 18)
  {
    uint256 amount = 100e6; // 100 of token0 (6 decimals)
    uint256 numerator = 2e18; // 2:1 rate
    uint256 denominator = 1e18;

    uint256 convertedAmount = fpmm.convertWithRate(amount, 1e6, 1e18, numerator, denominator);

    assertEq(convertedAmount, 200e18); // 100 * 2 * 10^12 = 200 * 10^18
  }

  function test_getAmountOut_whenToken0Input_shouldCalculateCorrectAmount()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    withOracleRate(2e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 10e18;

    uint256 amountInAfterFee = amountIn - ((amountIn * fpmm.protocolFee()) / 10000);

    uint256 expectedOut = fpmm.convertWithRate(amountInAfterFee, 1e18, 1e6, 2e18, 1e18);

    uint256 actualOut = fpmm.getAmountOut(amountIn, token0);

    assertEq(actualOut, expectedOut);
  }

  function test_getAmountOut_whenToken1Input_shouldCalculateCorrectAmount()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    withOracleRate(2e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 10e6;

    uint256 amountInAfterFee = amountIn - ((amountIn * fpmm.protocolFee()) / 10000);
    uint256 expectedOut = fpmm.convertWithRate(amountInAfterFee, 1e6, 1e18, 1e18, 2e18);
    uint256 actualOut = fpmm.getAmountOut(amountIn, token1);

    assertEq(actualOut, expectedOut);
  }

  function test_getPrices_whenReferenceRateSet_shouldReturnCorrectPrices()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    withOracleRate(2e24, 1e24)
    withMarketOpen(true)
    withRecentRate(true)
  {
    // FPMM scales the oracle rate down to 18 decimals
    uint256 expectedOraclePriceNumerator = 2e18;
    uint256 expectedOraclePriceDenominator = 1e18;

    uint256 expectedReservePriceNumerator = 200e18;
    uint256 expectedReservePriceDenominator = 100e18;

    (
      uint256 oraclePriceNumerator,
      uint256 oraclePriceDenominator,
      uint256 reservePriceNumerator,
      uint256 reservePriceDenominator,
      uint256 priceDifference,
      bool reservePriceAboveOraclePrice
    ) = fpmm.getPrices();

    assertEq(oraclePriceNumerator, expectedOraclePriceNumerator);
    assertEq(oraclePriceDenominator, expectedOraclePriceDenominator);
    assertEq(reservePriceNumerator, expectedReservePriceNumerator);
    assertEq(reservePriceDenominator, expectedReservePriceDenominator);
    assertEq(priceDifference, 0);
    assertEq(reservePriceAboveOraclePrice, false);
  }
}
