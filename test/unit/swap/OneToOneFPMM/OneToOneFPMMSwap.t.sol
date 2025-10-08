// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8;

import { OneToOneFPMMBaseTest } from "./OneToOneFPMMBaseTest.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

contract OneToOneFPMMSwapTest is OneToOneFPMMBaseTest {
  function setUp() public override {
    super.setUp();
  }

  function test_swap_whenSwappingToken0ForToken1At1to1_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amount0In = 100e18;
    // Even though oracle rate is 2:1, OneToOneFPMM always swaps at 1:1
    // Accounting for 0.3% LP fee: 100 * (1 - 0.003) = 99.7
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

  function test_swap_whenSwappingToken1ForToken0At1to1_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amount1In = 100e18;
    // Even though oracle rate is 2:1, OneToOneFPMM always swaps at 1:1
    // Accounting for 0.3% LP fee: 100 * (1 - 0.003) = 99.7
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

  function test_swap_whenSwappingWithProtocolFeeAt1to1_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withProtocolFee(20, protocolFeeRecipient)
    mintInitialLiquidity(18, 18)
    withOracleRate(2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amount0In = 100e18;
    // 1:1 rate regardless of oracle, 0.3% LP fee, 0.2% protocol fee
    // 100 * (1 - 0.003 - 0.002) = 99.5
    uint256 amount1Out = 99.50e18;
    uint256 protocolFee = (amount0In * 20) / 10000; // 0.2% protocol fee

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);
    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), protocolFee);

    assertEq(fpmm.reserve0(), initialReserve0 + amount0In - protocolFee);
    assertEq(fpmm.reserve1(), initialReserve1 - amount1Out);
  }

  function test_swap_whenOracleCallStillHappens_shouldNotRevertEvenIfOracleFails()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // The oracle is called to ensure breakerbox doesn't revert, but the rate is ignored
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.70e18;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);
  }

  function test_swap_whenSwappingWithDifferentDecimals_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(6, 18)
    mintInitialLiquidity(6, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 amount0In = 10e6; // 10 tokens of token0 (6 decimals)
    // At 1:1 rate with different decimals, 10 token0 = 10 token1
    // With 0.3% LP fee: 10 * (1 - 0.003) = 9.97
    uint256 amount1Out = 9.97e18; // 9.97 tokens of token1 (18 decimals)

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);

    assertEq(fpmm.reserve0(), initialReserve0 + amount0In);
    assertEq(fpmm.reserve1(), initialReserve1 - amount1Out);
  }

  function test_swap_whenTradingIsSuspended_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withTradingMode(TRADING_MODE_DISABLED)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    vm.expectRevert("OracleAdapter: TRADING_SUSPENDED");
    fpmm.swap(0, 10e18, BOB, "");
  }

  function test_swap_whenMarketIsClosed_shouldStillWork()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(false)
    withRecentRate(true)
  {
    // OneToOneFPMM is for stablecoin swaps (USD.m <-> USDC/USDT)
    // These should work even when FX markets are closed
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.70e18;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);
  }

  function test_swap_whenRateIsExpired_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(false)
  {
    // OneToOneFPMM checks rate freshness via ensureRateValid
    vm.expectRevert("OracleAdapter: NO_RECENT_RATE");
    fpmm.swap(0, 10e18, BOB, "");
  }
}
