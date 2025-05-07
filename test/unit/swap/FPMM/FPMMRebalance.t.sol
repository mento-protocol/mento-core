// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
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
    fpmm.setRebalanceThreshold(200); // 2%

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

    // Initial ratio: 0.5 token1 per token0
    // Oracle price: 1.2 token1 per token0
    // Current ratio is too high for token1, need to add token0 and remove token1
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

    // Initial ratio: 0.5 token1 per token0
    // Oracle price: 3 token1 per token0
    // Current ratio is too low for token1, need to add token1 and remove token0
    // Get token0 via flash loan and add token1 to rebalance

    // Borrow 17 token0 and exchange it for 51 token1
    // 83 / 251 = 3.024
    uint256 rebalanceAmount = 17e18;
    liquidityStrategy.executeRebalance(rebalanceAmount, 0);

    (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
    assertEq(finalReserve0, initialReserve0 - rebalanceAmount);
    assertEq(finalReserve1, initialReserve1 + (rebalanceAmount * oraclePrice) / 1e18);
  }
  //   function test_rebalance_both_tokens_success()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 18)
  //     mintInitialLiquidity(18, 18)
  //     setupMockExchange(1e18) // 1:1 rate
  //     setupRebalancer(18, 18)
  //     setupMockOracleRate(1.2e18, 1e18) // Oracle rate: 1 token0 = 1.2 token1
  //   {
  //     // Set a decently high rebalance threshold
  //     vm.prank(fpmm.owner());
  //     fpmm.setRebalanceThreshold(200); // 2%

  //     // Initial pool state
  //     (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

  //     // Borrow both tokens
  //     uint256 rebalanceAmount0 = 20e18;
  //     uint256 rebalanceAmount1 = 20e18;
  //     bool success = rebalancer.executeRebalance(rebalanceAmount0, rebalanceAmount1);

  //     assertTrue(success, "Rebalance should be successful");

  //     // Check rebalancer report of token usage
  //     uint256 token0Added = rebalancer.amountUsedForRebalance0();
  //     uint256 token1Added = rebalancer.amountUsedForRebalance1();
  //     assertEq(token0Added, rebalanceAmount0, "Should have added back token0");
  //     assertEq(token1Added, rebalanceAmount1, "Should have added back token1");

  //     // Check final pool state - should be unchanged for a healthy pool
  //     (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
  //     assertEq(finalReserve0, initialReserve0);
  //     assertEq(finalReserve1, initialReserve1);
  //   }

  //   function test_rebalance_threshold_not_met()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 18)
  //     mintInitialLiquidity(18, 18)
  //     setupMockExchange(1e18)
  //     setupRebalancer(18, 18)
  //     // Set a small price difference
  //     setupMockOracleRate(1.01e18, 1e18) // Only 1% different
  //   {
  //     // Set a high rebalance threshold
  //     vm.prank(fpmm.owner());
  //     fpmm.setRebalanceThreshold(200); // 2%

  //     // Try to rebalance
  //     uint256 rebalanceAmount = 20e18;
  //     vm.expectRevert("FPMM: PRICE_DIFFERENCE_TOO_SMALL");
  //     rebalancer.executeRebalance(0, rebalanceAmount);
  //   }

  //   function test_rebalance_excessive_value_loss()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 18)
  //     mintInitialLiquidity(18, 18)
  //     setupMockExchange(1e18)
  //     setupRebalancer(18, 18)
  //     setupMockOracleRate(1.5e18, 1e18) // Big difference to meet threshold
  //   {
  //     // Set a low rebalance threshold and low slippage
  //     vm.startPrank(fpmm.owner());
  //     fpmm.setRebalanceThreshold(100); // 1%
  //     fpmm.setAllowedSlippage(5); // 0.05%
  //     vm.stopPrank();

  //     // Configure rebalancer to partially rebalance (will lose value)
  //     rebalancer.setRebalanceOptions(false, true, true, true);

  //     // Try to rebalance - should fail due to excessive value loss
  //     uint256 rebalanceAmount = 20e18;
  //     vm.expectRevert("FPMM: EXCESSIVE_VALUE_LOSS");
  //     rebalancer.executeRebalance(0, rebalanceAmount);
  //   }

  //   function test_rebalance_does_not_improve_price()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 18)
  //     mintInitialLiquidity(18, 18)
  //     setupMockExchange(1e18)
  //     setupRebalancer(18, 18)
  //     setupMockOracleRate(1.5e18, 1e18) // Big difference to meet threshold
  //   {
  //     // Set a low rebalance threshold
  //     vm.prank(fpmm.owner());
  //     fpmm.setRebalanceThreshold(100); // 1%

  //     // Configure rebalancer to not improve price difference
  //     rebalancer.setRebalanceOptions(false, false, true, false);

  //     // Try to rebalance - should fail because price isn't improved
  //     uint256 rebalanceAmount = 20e18;
  //     vm.expectRevert("FPMM: PRICE_DIFFERENCE_NOT_IMPROVED");
  //     rebalancer.executeRebalance(0, rebalanceAmount);
  //   }

  //   function test_rebalance_with_different_decimals()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 6)
  //     mintInitialLiquidity(18, 6)
  //     setupMockExchange(1e18) // 1:1 rate (considering decimal differences)
  //     setupRebalancer(18, 6)
  //     setupMockOracleRate(1.2e18, 1e18) // Oracle rate adjusted for decimals
  //   {
  //     // Set a decently high rebalance threshold
  //     vm.prank(fpmm.owner());
  //     fpmm.setRebalanceThreshold(200); // 2%

  //     // Initial pool state
  //     (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

  //     // Borrow token1 (6 decimals)
  //     uint256 rebalanceAmount = 20e6; // 20 token1 with 6 decimals
  //     bool success = rebalancer.executeRebalance(0, rebalanceAmount);

  //     assertTrue(success, "Rebalance should be successful");

  //     // Check final pool state
  //     (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
  //     assertGt(finalReserve0, initialReserve0, "Token0 reserve should increase");
  //     assertEq(finalReserve1, initialReserve1, "Token1 reserve should remain the same");
  //   }

  //   function test_rebalance_with_protocol_fee()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 18)
  //     mintInitialLiquidity(18, 18)
  //     setupMockExchange(1e18)
  //     setupRebalancer(18, 18)
  //     setupMockOracleRate(1.5e18, 1e18)
  //   {
  //     // Set a higher protocol fee
  //     vm.startPrank(fpmm.owner());
  //     fpmm.setProtocolFee(50); // 0.5%
  //     fpmm.setRebalanceThreshold(100); // 1%
  //     fpmm.setAllowedSlippage(50); // 0.5%
  //     vm.stopPrank();

  //     // Initial pool state
  //     (uint256 initialReserve0, uint256 initialReserve1, ) = fpmm.getReserves();

  //     // Configure rebalancer for exact repayments
  //     rebalancer.setRebalanceOptions(false, false, true, true);

  //     // Rebalance with token0
  //     uint256 rebalanceAmount = 20e18;
  //     bool success = rebalancer.executeRebalance(rebalanceAmount, 0);

  //     assertTrue(success, "Rebalance should be successful");

  //     // Check final state - with protocol fee, we need to add more tokens to cover fee
  //     (uint256 finalReserve0, uint256 finalReserve1, ) = fpmm.getReserves();
  //     assertEq(finalReserve0, initialReserve0, "Token0 reserve should be the same");
  //     assertGt(finalReserve1, initialReserve1, "Token1 reserve should increase");
  //   }

  //   function test_rebalance_zero_amounts()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 18)
  //     mintInitialLiquidity(18, 18)
  //     setupMockExchange(1e18)
  //     setupRebalancer(18, 18)
  //     setupMockOracleRate(1.5e18, 1e18)
  //   {
  //     // Try to rebalance with zero amounts
  //     vm.expectRevert("FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
  //     rebalancer.executeRebalance(0, 0);
  //   }

  //   function test_rebalance_insufficient_reserves()
  //     public
  //     initializeFPMM_withDecimalTokens(18, 18)
  //     mintInitialLiquidity(18, 18)
  //     setupMockExchange(1e18)
  //     setupRebalancer(18, 18)
  //     setupMockOracleRate(1.5e18, 1e18)
  //   {
  //     // Try to rebalance with too large amounts
  //     uint256 tooLargeAmount0 = 101e18; // More than reserve0
  //     uint256 tooLargeAmount1 = 201e18; // More than reserve1

  //     vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
  //     rebalancer.executeRebalance(tooLargeAmount0, 0);

  //     vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
  //     rebalancer.executeRebalance(0, tooLargeAmount1);
  //   }

  // Helper function to calculate price difference in basis points
  function calculatePriceDifferenceInBps(
    uint256 reserve0,
    uint256 reserve1,
    uint256 rateNumerator,
    uint256 rateDenominator
  ) internal view returns (uint256) {
    uint256 oraclePrice = rateNumerator / rateDenominator;
    uint256 decimals0 = 10 ** 18;
    uint256 decimals1 = 10 ** 18;
    uint256 reserveRatio = (reserve0 * decimals1) / (reserve1 * decimals0);

    if (oraclePrice > reserveRatio) {
      return ((oraclePrice - reserveRatio) * 10000) / oraclePrice;
    } else {
      return ((reserveRatio - oraclePrice) * 10000) / oraclePrice;
    }
  }
}
