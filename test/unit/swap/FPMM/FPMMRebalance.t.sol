// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { MockLiquidityStrategy } from "./helpers/MockLiquidityStrategy.sol";

import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

contract FPMMRebalanceTest is FPMMBaseTest {
  MockLiquidityStrategy public liquidityStrategy;

  function setUp() public override {
    super.setUp();
  }

  modifier setupRebalancer(uint8 decimals0, uint8 decimals1) {
    // Set a decently high rebalance threshold for testing
    vm.prank(fpmm.owner());

    liquidityStrategy = new MockLiquidityStrategy(address(fpmm), token0, token1);

    vm.prank(fpmm.owner());
    fpmm.setLiquidityStrategy(address(liquidityStrategy), true);

    deal(token0, address(liquidityStrategy), 1000 * 10 ** decimals0);
    deal(token1, address(liquidityStrategy), 1000 * 10 ** decimals1);
    _;
  }

  function test_rebalance_whenUnauthorized_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 rebalanceAmount = 10e18;

    // Try to call rebalance directly without being a trusted strategy
    vm.expectRevert("FPMM: NOT_LIQUIDITY_STRATEGY");
    fpmm.rebalance(rebalanceAmount, 0, "Unauthorized rebalance");
  }

  function test_rebalance_whenThresholdNotMet_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    // Set a small price difference
    withOracleRate(2.01e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // Current internal price: 2 token1 per token0
    // Oracle price: 2.01 token1 per token0
    // Price difference is too small to rebalance
    // .5% < 5% (threshold)

    uint256 rebalanceAmount = 20e18;
    vm.expectRevert("FPMM: PRICE_DIFFERENCE_TOO_SMALL");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_whenExcessiveValueLoss_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.2e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    (
      uint256 oraclePriceNumerator,
      uint256 oraclePriceDenominator,
      uint256 reservePriceNumerator,
      uint256 reservePriceDenominator,
      uint256 priceDifference,
      bool reservePriceAboveOraclePrice
    ) = fpmm.getPrices();
    assertEq(oraclePriceNumerator, 1.2e18);
    assertEq(oraclePriceDenominator, 1e18);
    assertEq(reservePriceNumerator, 200e18);
    assertEq(reservePriceDenominator, 100e18);
    assertEq(priceDifference, 6666);
    assertEq(reservePriceAboveOraclePrice, true);

    // Initial reserve price: 2 token1 per token0
    // Oracle price: 1.2 token1 per token0
    // Current price is too high, need to add token0 and remove token1
    // Get token1 via flash loan and add token0 to rebalance

    // init reserve value: 320
    // Borrow 40 token1 and exchange it for 33.33 token0
    // 10 % profit -> returns 30 token0
    liquidityStrategy.setProfitPercentage(1000);

    // reserve0 = 130.0 reserve 1 = 160
    // final reserve value = 130 * 1.2 + 160 = 316
    // 1.25 % loss > .5% threshold it should revert

    uint256 rebalanceAmount = 40e18;
    vm.expectRevert("FPMM: INSUFFICIENT_AMOUNT_0_IN");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);

    liquidityStrategy.setProfitPercentage(300);
    // 3 % profit -> returns 32.33 tokens -> takes 1 token as incentive
    // 32.33 * .5% = 0.16165
    vm.expectRevert("FPMM: INSUFFICIENT_AMOUNT_0_IN");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);

    liquidityStrategy.setProfitPercentage(30);
    // .3 % profit -> returns 33.23 tokens -> takes .1 token as incentive
    // 33.23 * .5% = 0.16615
    // incentive is smaller than allowed, it should not revert
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_whenPriceNotImproved_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.5e18, 1e18) // Big difference to meet threshold
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // Try to rebalance - should fail because price isn't improved
    uint256 rebalanceAmount = 20e18;
    vm.expectRevert("FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");
    liquidityStrategy.executeRebalance(rebalanceAmount, 0);
  }

  function test_rebalance_whenInsufficientReserves_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.5e18, 1e18)
  {
    // Try to rebalance with too large amounts
    uint256 tooLargeAmount0 = 101e18; // More than reserve0
    uint256 tooLargeAmount1 = 201e18; // More than reserve1

    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
    liquidityStrategy.executeRebalance(tooLargeAmount0, 0);

    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
    liquidityStrategy.executeRebalance(0, tooLargeAmount1);
  }

  function test_rebalance_whenTradingSuspended_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.2e18, 1e18)
    withTradingMode(TRADING_MODE_DISABLED)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 rebalanceAmount = 10e18;
    vm.expectRevert("OracleAdapter: TRADING_SUSPENDED");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_whenMarketIsClosed_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.2e18, 1e18)
    withFXMarketOpen(false)
    withRecentRate(true)
  {
    uint256 rebalanceAmount = 10e18;
    vm.expectRevert("OracleAdapter: FX_MARKET_CLOSED");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_whenRateIsExpired_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(false)
  {
    uint256 rebalanceAmount = 10e18;
    vm.expectRevert("OracleAdapter: NO_RECENT_RATE");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_whenMovingInWrongDirection_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(3e18, 1e18) // Oracle rate: 1 token0 = 3 token1
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // Initial reserve price: 2 token1 per token0
    // Oracle price: 3 token1 per token0
    // Current price is too low, need to add token1 and remove token0
    // Get token0 via flash loan and add token1 to rebalance

    // Borrow 17 token0 and exchange it for 51 token1
    // 251 / 83 = 3.024  Price moved from low to high
    // Should revert because price moved in wrong direction
    uint256 rebalanceAmount = 17e18;
    vm.expectRevert("FPMM: PRICE_DIFFERENCE_MOVED_IN_WRONG_DIRECTION");
    liquidityStrategy.executeRebalance(rebalanceAmount, 0);
  }

  function test_rebalance_whenToken0OutAndToken0In_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 rebalanceAmount = 10e18;
    liquidityStrategy.setShouldMovePrice(false);
    vm.expectRevert("FPMM: REBALANCE_DIRECTION_INVALID");
    liquidityStrategy.executeRebalance(rebalanceAmount, 0);
  }

  function test_rebalance_whenToken1OutAndToken1In_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.2e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 rebalanceAmount = 10e18;
    liquidityStrategy.setShouldMovePrice(false);
    vm.expectRevert("FPMM: REBALANCE_DIRECTION_INVALID");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_whenAddingToken0_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(1.2e24, 1e24) // Oracle rate: 1 token0 = 1.2 token1
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    (
      uint256 oraclePriceNumerator,
      uint256 oraclePriceDenominator,
      uint256 reservePriceNumerator,
      uint256 reservePriceDenominator,
      uint256 priceDifference,
      bool reservePriceAboveOraclePrice
    ) = fpmm.getPrices();

    assertEq(oraclePriceNumerator, 1.2e18);
    assertEq(oraclePriceDenominator, 1e18);
    assertEq(reservePriceNumerator, 200e18);
    assertEq(reservePriceDenominator, 100e18);
    // (2-1.2)/1.2 = 66.66% in bps
    assertEq(priceDifference, 6666);
    assertEq(reservePriceAboveOraclePrice, true);

    (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

    // Initial reserve price: 2 token1 per token0
    // Oracle price: 1.2 token1 per token0
    // Current price is too high, need to add token0 and remove token1
    // Get token1 via flash loan and add token0 to rebalance

    // Borrow 40 token1 and exchange it for 33.33 token0
    // 133.33 / 160 = 1.2
    uint256 rebalanceAmount = 40e18;
    liquidityStrategy.executeRebalance(0, rebalanceAmount);

    (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
    assertEq(finalReserve0, initialReserve0 + (rebalanceAmount * oraclePriceDenominator) / oraclePriceNumerator);
    assertEq(finalReserve1, initialReserve1 - rebalanceAmount);
  }

  function test_rebalance_whenAddingToken1_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    withOracleRate(3e24, 1e24) // Oracle rate: 1 token0 = 3 token1
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    (
      uint256 oraclePriceNumerator,
      uint256 oraclePriceDenominator,
      uint256 reservePriceNumerator,
      uint256 reservePriceDenominator,
      uint256 priceDifference,
      bool reservePriceAboveOraclePrice
    ) = fpmm.getPrices();
    assertEq(oraclePriceNumerator, 3e18);
    assertEq(oraclePriceDenominator, 1e18);
    assertEq(reservePriceNumerator, 200e18);
    assertEq(reservePriceDenominator, 100e18);
    // (3-2)/3 = 33.33% in bps
    assertEq(priceDifference, 3333);
    assertEq(reservePriceAboveOraclePrice, false);

    (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

    // Initial reserve price: 2 token1 per token0
    // Oracle price: 3 token1 per token0
    // Current price is too low, need to add token1 and remove token0
    // Get token0 via flash loan and add token1 to rebalance

    // Borrow 16 token0 and exchange it for 48 token1
    // 248 / 84 = 2.952
    uint256 rebalanceAmount = 16e18;
    liquidityStrategy.executeRebalance(rebalanceAmount, 0);

    (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
    assertEq(finalReserve0, initialReserve0 - rebalanceAmount);
    assertEq(finalReserve1, initialReserve1 + (rebalanceAmount * oraclePriceNumerator) / oraclePriceDenominator);
  }

  function test_rebalance_whenDifferentDecimals_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    setupRebalancer(18, 6)
    withOracleRate(1.2e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    (
      uint256 oraclePriceNumerator,
      uint256 oraclePriceDenominator,
      uint256 reservePriceNumerator,
      uint256 reservePriceDenominator,
      uint256 priceDifference,
      bool reservePriceAboveOraclePrice
    ) = fpmm.getPrices();
    assertEq(oraclePriceNumerator, 1.2e18);
    assertEq(oraclePriceDenominator, 1e18);
    assertEq(reservePriceNumerator, 200e18);
    assertEq(reservePriceDenominator, 100e18);
    // (2-1.2)/1.2 = 66.66% in bps
    assertEq(priceDifference, 6666);
    assertEq(reservePriceAboveOraclePrice, true);

    (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

    // Initial reserve price: 2 token1 per token0
    // Oracle price: 1.2 token1 per token0
    // Current price is too high, need to add token0 and remove token1
    // Get token1 via flash loan and add token0 to rebalance

    // Borrow 40 token1 and exchange it for 33.33 token0
    // 133.33 / 160 = 1.2
    uint256 rebalanceAmount = 40e6;
    uint256 expectedAmount0In = liquidityStrategy.convertWithRate(
      rebalanceAmount,
      1e6,
      1e18,
      oraclePriceDenominator,
      oraclePriceNumerator
    );
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
    (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
    assertEq(finalReserve0, initialReserve0 + expectedAmount0In);
    assertEq(finalReserve1, initialReserve1 - rebalanceAmount);
  }

  function test_rebalance_whenInitialMintIsUnbalanced_shouldNotFavorInitialMinter()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    setupRebalancer(18, 6)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // Alice mints 1000e18 token0 and 20 token1 to a Pool that is 1:1
    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), 1_000e18);
    IERC20(token1).transfer(address(fpmm), 20e6);
    fpmm.mint(ALICE);
    vm.stopPrank();

    // Pool is rebalanced to ~510e18, ~510e6 => 1:1
    liquidityStrategy.executeRebalance(490e18, 0);

    assertApproxEqRel(fpmm.reserve0(), 510e18, 0.0001e18);
    assertApproxEqRel(fpmm.reserve1(), 510e6, 0.0001e18);

    // Bob mints 510e18 token0 and 510e6 token1 to the same Pool
    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), 510e18);
    IERC20(token1).transfer(address(fpmm), 510e6);
    fpmm.mint(BOB);
    vm.stopPrank();

    // Alice and Bob should have roughly the same amount of liquidity tokens
    // since both put in roughly the same amount of liquidity
    assertApproxEqRel(fpmm.balanceOf(ALICE), fpmm.balanceOf(BOB), 0.0001e18);

    uint256 aliceToken0BalanceBefore = IERC20(token0).balanceOf(ALICE);
    uint256 aliceToken1BalanceBefore = IERC20(token1).balanceOf(ALICE);

    // Alice burns her liquidity
    vm.startPrank(ALICE);
    IERC20(address(fpmm)).transfer(address(fpmm), fpmm.balanceOf(ALICE));
    fpmm.burn(ALICE);
    vm.stopPrank();

    uint256 aliceToken0Received = IERC20(token0).balanceOf(ALICE) - aliceToken0BalanceBefore;
    uint256 aliceToken1Received = IERC20(token1).balanceOf(ALICE) - aliceToken1BalanceBefore;

    // Alice should have received ~510e18 token0 and ~510e6 token1
    assertApproxEqRel(aliceToken0Received, 510e18, 0.0001e18);
    assertApproxEqRel(aliceToken1Received, 510e6, 0.0001e18);
  }
}
