// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

contract FPMMSwapTest is FPMMBaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_swap_whenCalledWith0AmountOut_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.expectRevert("FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    fpmm.swap(0, 0, address(this), "");
  }

  function test_swap_whenCalledWithInsufficientLiquidity_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
    fpmm.swap(100e18, 0, address(this), "");
  }

  function test_swap_whenCalledWithInvalidToAddress_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    deal(token0, address(fpmm), 100e18);

    vm.expectRevert("FPMM: INVALID_TO_ADDRESS");
    fpmm.swap(50e18, 0, token0, "");
  }

  function test_swap_whenReserveValueDecreased_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    deal(token0, address(this), 100e18);
    IERC20(token0).transfer(address(fpmm), 100e18);

    vm.expectRevert("FPMM: RESERVE_VALUE_DECREASED");
    fpmm.swap(0, 100e18, address(this), "");
  }

  function test_swap_whenSwappingToken0ForToken1_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.70e18;

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);

    assertEq(fpmm.reserve0(), initialReserve0 + amount0In);
    assertEq(fpmm.reserve1(), initialReserve1 - amount1Out);
  }

  function test_swap_whenSwappingToken1ForToken0_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amount1In = 100e18;
    uint256 amount0Out = 99.7e18;

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(ALICE);
    IERC20(token1).transfer(address(fpmm), amount1In);
    fpmm.swap(amount0Out, 0, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(CHARLIE), amount0Out);

    assertEq(fpmm.reserve0(), initialReserve0 - amount0Out);
    assertEq(fpmm.reserve1(), initialReserve1 + amount1In);
  }

  function test_swap_whenUsingDifferentExchangeRate_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(2e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    // Swap 100 token0 for 199.4 token1 (after 0.3% fee)
    uint256 amount0In = 100e18;
    uint256 amount1Out = 199.4e18;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();
    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);
  }

  function test_swap_whenUsingDifferentDecimals_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    withOracleRate(1e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    // Swap 100 token0 (18 decimals) for 99.7 token1 (6 decimals)
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e6;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);

    uint256 amount1In = 100e6;
    uint256 amount0Out = 99.7e18;

    vm.startPrank(ALICE);
    IERC20(token1).transfer(address(fpmm), amount1In);
    fpmm.swap(amount0Out, 0, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(CHARLIE), amount0Out);
  }

  function test_swap_whenUsingDifferentFees_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    // Change fee to 1%
    vm.prank(fpmm.owner());
    fpmm.setProtocolFee(100);

    uint256 amount0In = 100e18;
    uint256 amount1Out = 99e18;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);

    // Change fee to 0%
    vm.prank(fpmm.owner());
    fpmm.setProtocolFee(0);

    uint256 amount1In = 100e18;
    uint256 amount0Out = 100e18;

    vm.startPrank(ALICE);
    IERC20(token1).transfer(address(fpmm), amount1In);
    fpmm.swap(amount0Out, 0, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(CHARLIE), amount0Out);
  }

  function test_swap_whenUsingComplexExchangeRate_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1234e18, 5678e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amountIn = 100e18;

    uint256 expectedAmountOut = 21667805565339908418; // (100e18 * 1234e18 / 5678e18) * (997 / 1000)

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amountIn);
    fpmm.swap(0, expectedAmountOut, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), expectedAmountOut);
  }

  function test_swap_whenExecuting_shouldUpdateTimestamp()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withMarketOpen(true)
    withRecentRate(true)
  {
    uint256 initialTimestamp;
    (, , initialTimestamp) = fpmm.getReserves();

    vm.warp(block.timestamp + 1000);

    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e18;

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, BOB, "");

    uint256 newTimestamp;
    (, , newTimestamp) = fpmm.getReserves();

    assertEq(newTimestamp, block.timestamp);
    assertGt(newTimestamp, initialTimestamp);
  }

  function test_swap_whenTradingIsSuspended_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withTradingMode(TRADING_MODE_DISABLED)
    withMarketOpen(true)
    withRecentRate(true)
  {
    vm.expectRevert("FPMM: TRADING_SUSPENDED");
    fpmm.swap(0, 10e18, BOB, "");
  }

  function test_swap_whenMarketIsClosed_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withMarketOpen(false)
    withRecentRate(true)
  {
    vm.expectRevert("FPMM: MARKET_CLOSED");
    fpmm.swap(0, 10e18, BOB, "");
  }

  function test_swap_whenRateIsExpired_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withMarketOpen(true)
    withRecentRate(false)
  {
    vm.expectRevert("FPMM: NO_RECENT_RATE");
    fpmm.swap(0, 10e18, BOB, "");
  }
}
