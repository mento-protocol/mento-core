// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { MockLiquidityStrategy } from "./helpers/MockLiquidityStrategy.sol";

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

  function test_rebalance_unauthorized() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
    uint256 rebalanceAmount = 10e18;

    // Try to call rebalance directly without being a trusted strategy
    vm.expectRevert("FPMM: NOT_LIQUIDITY_STRATEGY");
    fpmm.rebalance(rebalanceAmount, 0, address(this), "Unauthorized rebalance");
  }

  function test_rebalance_token0_success()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    setupMockOracleRate(1.2e18, 1e18) // Oracle rate: 1 token0 = 1.2 token1
  {
    (uint256 oraclePrice, uint256 reservePrice, , ) = fpmm.getPrices();
    assertEq(oraclePrice, 1.2e18);
    assertEq(reservePrice, 2e18);

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
    assertEq(finalReserve0, initialReserve0 + (rebalanceAmount * 1e18) / oraclePrice);
    assertEq(finalReserve1, initialReserve1 - rebalanceAmount);
  }

  function test_rebalance_token1_success()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    setupMockOracleRate(3e18, 1e18) // Oracle rate: 1 token0 = 3 token1
  {
    (uint256 oraclePrice, uint256 reservePrice, , ) = fpmm.getPrices();
    assertEq(oraclePrice, 3e18);
    assertEq(reservePrice, 2e18);

    (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

    // Initial reserve price: 2 token1 per token0
    // Oracle price: 3 token1 per token0
    // Current price is too low, need to add token1 and remove token0
    // Get token0 via flash loan and add token1 to rebalance

    // Borrow 17 token0 and exchange it for 51 token1
    // 251 / 83 = 3.024
    uint256 rebalanceAmount = 17e18;
    liquidityStrategy.executeRebalance(rebalanceAmount, 0);

    (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
    assertEq(finalReserve0, initialReserve0 - rebalanceAmount);
    assertEq(finalReserve1, initialReserve1 + (rebalanceAmount * oraclePrice) / 1e18);
  }

  function test_rebalance_threshold_not_met()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    // Set a small price difference
    setupMockOracleRate(2.01e18, 1e18)
  {
    // Current internal price: 2 token1 per token0
    // Oracle price: 2.01 token1 per token0
    // Price difference is too small to rebalance
    // .5% < 5% (threshold)

    uint256 rebalanceAmount = 20e18;
    vm.expectRevert("FPMM: PRICE_DIFFERENCE_TOO_SMALL");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_excessive_value_loss()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    setupMockOracleRate(1.2e18, 1e18)
  {
    (uint256 oraclePrice, uint256 reservePrice, , ) = fpmm.getPrices();
    assertEq(oraclePrice, 1.2e18);
    assertEq(reservePrice, 2e18);

    // Initial reserve price: 2 token1 per token0
    // Oracle price: 1.2 token1 per token0
    // Current price is too high, need to add token0 and remove token1
    // Get token1 via flash loan and add token0 to rebalance

    // init reserve value: 320
    // Borrow 40 token1 and exchange it for 33.33 token0
    // 10 % profit -> returns 30 token0
    liquidityStrategy.setProfitPercentage(10);

    // reserve0 = 130.0 reserve 1 = 160
    // final reserve value = 130 * 1.2 + 160 = 316
    // 1.25 % loss > .5% threshold it should revert

    uint256 rebalanceAmount = 40e18;
    vm.expectRevert("FPMM: EXCESSIVE_VALUE_LOSS");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);

    // 3 % profit -> returns 32.33 tokens
    liquidityStrategy.setProfitPercentage(3);

    // reserve0 = 132.33 reserve 1 = 160
    // final reserve value = 132.33 * 1.2 + 160 = 318.796
    // .375% loss < .5% threshold it should not revert

    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_does_not_improve_price()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    setupMockOracleRate(1.5e18, 1e18) // Big difference to meet threshold
  {
    liquidityStrategy.setShouldImprovePrice(false);

    // Try to rebalance - should fail because price isn't improved
    uint256 rebalanceAmount = 20e18;
    vm.expectRevert("FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_pool_not_rebalanced()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    setupMockOracleRate(1.2e18, 1e18)
  {
    (uint256 oraclePrice, uint256 reservePrice, , ) = fpmm.getPrices();
    assertEq(oraclePrice, 1.2e18);
    assertEq(reservePrice, 2e18);

    // Borrow 20 token1 and exchange it for 16.66 token0
    // 180 / 116.66 = 1.54
    uint256 rebalanceAmount = 20e18;
    vm.expectRevert("FPMM: POOL_NOT_REBALANCED");
    liquidityStrategy.executeRebalance(0, rebalanceAmount);
  }

  function test_rebalance_with_different_decimals()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    setupRebalancer(18, 6)
    setupMockOracleRate(1.2e18, 1e18)
  {
    (uint256 oraclePrice, uint256 reservePrice, , ) = fpmm.getPrices();
    assertEq(oraclePrice, 1.2e18);
    assertEq(reservePrice, 2e18);

    (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

    // Initial reserve price: 2 token1 per token0
    // Oracle price: 1.2 token1 per token0
    // Current price is too high, need to add token0 and remove token1
    // Get token1 via flash loan and add token0 to rebalance

    // Borrow 40 token1 and exchange it for 33.33 token0
    // 133.33 / 160 = 1.2
    uint256 rebalanceAmount = 40e6;
    liquidityStrategy.executeRebalance(0, rebalanceAmount);

    (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
    assertEq(finalReserve0, initialReserve0 + ((rebalanceAmount * 10 ** 13) / 12));
    assertEq(finalReserve1, initialReserve1 - rebalanceAmount);
  }

  function test_rebalance_insufficient_reserves()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupRebalancer(18, 18)
    setupMockOracleRate(1.5e18, 1e18)
  {
    // Try to rebalance with too large amounts
    uint256 tooLargeAmount0 = 101e18; // More than reserve0
    uint256 tooLargeAmount1 = 201e18; // More than reserve1

    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
    liquidityStrategy.executeRebalance(tooLargeAmount0, 0);

    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
    liquidityStrategy.executeRebalance(0, tooLargeAmount1);
  }
}
