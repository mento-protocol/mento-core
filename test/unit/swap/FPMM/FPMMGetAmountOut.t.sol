// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

contract FPMMGetAmountOutTest is FPMMBaseTest {
  address public referenceRateFeedID;

  function setUp() public override {
    super.setUp();
    referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");

    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);
  }

  function test_getAmountOut_shouldRevert_whenAmountIsZero() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.expectRevert("FPMM: INSUFFICIENT_INPUT_AMOUNT");
    fpmm.getAmountOut(0, token0);
  }

  function test_getAmountOut_shouldRevert_whenTokenIsInvalid() public initializeFPMM_withDecimalTokens(18, 18) {
    address invalidToken = makeAddr("INVALID_TOKEN");

    vm.expectRevert("FPMM: INVALID_TOKEN");
    fpmm.getAmountOut(100, invalidToken);
  }

  function test_getAmountOut_shouldReturnCorrectAmount_whenRateIsOneToOne()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    // price of token 0 to token 1 is 0.1
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(10e18, 100e18));

    uint256 amountIn = 100e18;
    uint256 amountOut = fpmm.getAmountOut(amountIn, token0);

    uint256 expectedAmountOut = 9.97e18; // 10e18 - 0.3% fee
    assertEq(amountOut, expectedAmountOut);

    amountOut = fpmm.getAmountOut(amountIn, token1);
    expectedAmountOut = 997e18; // 1000e18 - 0.3% fee
    assertEq(amountOut, expectedAmountOut);
  }

  function test_getAmountOut_shouldRespectProtocolFee() public initializeFPMM_withDecimalTokens(18, 18) {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(10e18, 100e18));

    uint256 amountIn = 100e18;

    // Change fee to 1%
    fpmm.setProtocolFee(100); // 100 basis points = 1%
    uint256 expectedAmountOut = 9.9e18; // 10e18 - 1% fee
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);

    // Change fee to 0%
    fpmm.setProtocolFee(0);
    expectedAmountOut = 10e18; // No fee
    assertEq(fpmm.getAmountOut(amountIn, token0), expectedAmountOut);
  }

  function test_getAmountOut_shouldConvertCorrectly_withExchangeRate() public initializeFPMM_withDecimalTokens(18, 18) {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(2e18, 1e18));

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

  function test_getAmountOut_shouldHandleDifferentDecimals() public initializeFPMM_withDecimalTokens(18, 6) {
    // Mock the sortedOracles.medianRate call to return 1:1 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

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

  function test_getAmountOut_shouldHandleDifferentDecimals_withExchangeRate()
    public
    initializeFPMM_withDecimalTokens(18, 6)
  {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(10e18, 100e18));

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

  function test_getAmountOut_shouldHandleComplexRates() public initializeFPMM_withDecimalTokens(18, 18) {
    // Set up the mock and reference rate feed ID
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock the sortedOracles.medianRate call to return 1234:5678 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1234e18, 5678e18));

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
}
