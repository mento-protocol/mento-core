// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract CDPLiquidityStrategy_RebalanceTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ============ Contraction Token 0 Debt Tests ================ */
  /* ============================================================ */

  function test_rebalance_whenToken0DebtPoolPriceBelowRebalanceThreshold_shouldContract()
    public
    fpmmToken0Debt(12, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // COP/USD rate: 1 USD = ~3920 COP
    uint256 oracleNum = 255050000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide initial reserves (3.9M COP and 1M USD)
    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNum, oracleDen);

    mockCollateralRegistryOracleRate(oracleNum, oracleDen);

    // Debalance FPMM by swapping 200k USD worth of COP into the pool
    swapIn(debtToken, 784_150_001e12);

    // Snapshot before rebalance
    (, , , , bool poolPriceAboveBefore, , uint256 priceDiffBefore) = fpmm.getRebalancingState();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 protocolFeeRecipientBalanceBefore = IERC20(debtToken).balanceOf(address(protocolFeeRecipient));
    uint256 collateralRegistryBalanceBefore = IERC20(debtToken).balanceOf(address(mockCollateralRegistry));

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , bool poolPriceAboveAfter, , uint256 priceDiffAfter) = fpmm.getRebalancingState();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 protocolFeeRecipientBalanceAfter = IERC20(debtToken).balanceOf(address(protocolFeeRecipient));
    uint256 collateralRegistryBalanceAfter = IERC20(debtToken).balanceOf(address(mockCollateralRegistry));
    // Allow for 1 basis point difference due to rounding and precision
    assertApproxEqAbs(priceDiffAfter, 500, 1, "Price should be at rebalance threshold");
    assertFalse(poolPriceAboveAfter, "Pool price should still be below oracle");
    assertLt(reserve0After, reserve0Before, "Debt reserves should decrease");
    assertGt(reserve1After, reserve1Before, "Collateral reserves should increase");
    assertReserveValueIncentives(reserve0Before, reserve1Before, reserve0After, reserve1After);
    assertRebalanceAmountIncentives(reserve0Before - reserve0After, reserve1After - reserve1Before, true);
    assertIncentive(
      reserve0Before - reserve0After,
      protocolFeeRecipientBalanceAfter - protocolFeeRecipientBalanceBefore,
      25
    );
    assertIncentive(
      reserve0Before - reserve0After,
      collateralRegistryBalanceAfter - collateralRegistryBalanceBefore,
      25
    );
  }

  /* ============================================================ */
  /* ============ Contraction Token 1 Debt Tests =============== */
  /* ============================================================ */

  function test_rebalance_whenToken1DebtAndPoolPriceAbove_shouldContract()
    public
    fpmmToken1Debt(18, 6)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // USDC/USD rate (nearly 1:1)
    uint256 oracleNum = 999884980000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide initial reserves
    provideFPMMReserves(10_000e6, 10_000e18, false);
    setOracleRate(oracleNum, oracleDen);

    // For token1 debt, oracle rate is inverted
    mockCollateralRegistryOracleRate(oracleDen, oracleNum);

    // Debalance FPMM by swapping 5k USD into the pool
    swapIn(debtToken, 5_000e18);

    // Snapshot before rebalance
    (, , , , bool poolPriceAboveBefore, , uint256 priceDiffBefore) = fpmm.getRebalancingState();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 protocolFeeRecipientBalanceBefore = IERC20(debtToken).balanceOf(address(protocolFeeRecipient));
    uint256 collateralRegistryBalanceBefore = IERC20(debtToken).balanceOf(address(mockCollateralRegistry));

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, address(0), 0, address(0), 0);
    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , bool poolPriceAboveAfter, , uint256 priceDiffAfter) = fpmm.getRebalancingState();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 protocolFeeRecipientBalanceAfter = IERC20(debtToken).balanceOf(address(protocolFeeRecipient));
    uint256 collateralRegistryBalanceAfter = IERC20(debtToken).balanceOf(address(mockCollateralRegistry));

    assertEq(priceDiffAfter, 500, "Price should be at rebalance threshold");
    assertTrue(poolPriceAboveAfter, "Pool price should still be above oracle");
    assertGt(reserve0After, reserve0Before, "Collateral reserves should increase");
    assertLt(reserve1After, reserve1Before, "Debt reserves should decrease");
    assertReserveValueIncentives(reserve0Before, reserve1Before, reserve0After, reserve1After);
    assertRebalanceAmountIncentives(reserve1Before - reserve1After, reserve0After - reserve0Before, false);
    assertIncentive(
      reserve1Before - reserve1After,
      protocolFeeRecipientBalanceAfter - protocolFeeRecipientBalanceBefore,
      25
    );
    assertIncentive(
      reserve1Before - reserve1After,
      collateralRegistryBalanceAfter - collateralRegistryBalanceBefore,
      25
    );
  }

  /* ============================================================ */
  /* ============== Expansion Token 0 Debt Tests =============== */
  /* ============================================================ */

  function test_rebalance_whenToken0DebtPoolPriceAboveAndEnoughInStabilityPool_shouldExpandToRebalanceThreshold()
    public
    fpmmToken0Debt(12, 6)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // JPY/USD rate: 1 USD = ~148 JPY
    uint256 oracleNum = 6755340000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide ~550k USD to both reserves
    provideFPMMReserves(81_419_800e12, 550_000e6, true);
    setOracleRate(oracleNum, oracleDen);

    // Debalance FPMM by swapping 75k USD worth of collateral into the pool
    swapIn(collToken, 75_000e6);

    // Set stability pool balance high enough to cover expansion
    setStabilityPoolBalance(debtToken, 100_000_000e12);
    setMockSystemParamsMinBoldAfterRebalance(1e18);

    // Snapshot before rebalance
    (, , , , bool poolPriceAboveBefore, , uint256 priceDiffBefore) = fpmm.getRebalancingState();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 stabilityPoolDebtBefore = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBefore = IERC20(collToken).balanceOf(address(mockStabilityPool));
    uint256 protocolFeeRecipientBalanceBefore = IERC20(collToken).balanceOf(address(protocolFeeRecipient));

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , bool poolPriceAboveAfter, , uint256 priceDiffAfter) = fpmm.getRebalancingState();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 stabilityPoolDebtAfter = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollAfter = IERC20(collToken).balanceOf(address(mockStabilityPool));
    uint256 protocolFeeRecipientBalanceAfter = IERC20(collToken).balanceOf(address(protocolFeeRecipient));

    // Verify results
    assertTrue(poolPriceAboveAfter, "Pool price should still be above oracle");
    assertEq(priceDiffAfter, 500, "Price difference should be at rebalance threshold");
    assertEq(
      stabilityPoolDebtBefore - (reserve0After - reserve0Before),
      stabilityPoolDebtAfter,
      "Stability pool debt should decrease by expansion amount"
    );
    // 25 bps of the expansion amount is taken as protocol incentive
    assertEq(
      stabilityPoolCollBefore + (reserve1Before - reserve1After) - (((reserve1Before - reserve1After) * 25) / 10_000),
      stabilityPoolCollAfter,
      "Stability pool collateral should increase"
    );
    assertGt(reserve0After, reserve0Before, "Debt reserves should increase");
    assertLt(reserve1After, reserve1Before, "Collateral reserves should decrease");
    assertReserveValueIncentives(reserve0Before, reserve1Before, reserve0After, reserve1After);
    assertRebalanceAmountIncentives(reserve1Before - reserve1After, reserve0After - reserve0Before, false);
    assertIncentive(
      reserve1Before - reserve1After,
      protocolFeeRecipientBalanceAfter - protocolFeeRecipientBalanceBefore,
      25
    );
  }

  function test_rebalance_whenToken0DebtPoolPriceAboveAndLimitedStabilityPoolFunds_shouldExpandPartially()
    public
    fpmmToken0Debt(12, 6)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // Setup similar to above but with limited stability pool
    uint256 oracleNum = 6755340000000000;
    uint256 oracleDen = 1e18;

    provideFPMMReserves(81_419_800e12, 550_000e6, true);
    setOracleRate(oracleNum, oracleDen);

    swapIn(collToken, 75_000e6);

    // Set stability pool balance insufficient for full expansion
    setStabilityPoolBalance(debtToken, 3_000_000e12);
    setMockSystemParamsMinBoldAfterRebalance(1e18);

    // Snapshot before rebalance
    (, , , , bool poolPriceAboveBefore, , uint256 priceDiffBefore) = fpmm.getRebalancingState();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 stabilityPoolDebtBefore = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBefore = IERC20(collToken).balanceOf(address(mockStabilityPool));
    uint256 protocolFeeRecipientBalanceBefore = IERC20(collToken).balanceOf(address(protocolFeeRecipient));

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);
    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , bool poolPriceAboveAfter, , uint256 priceDiffAfter) = fpmm.getRebalancingState();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 stabilityPoolDebtAfter = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollAfter = IERC20(collToken).balanceOf(address(mockStabilityPool));
    uint256 protocolFeeRecipientBalanceAfter = IERC20(collToken).balanceOf(address(protocolFeeRecipient));

    // Verify partial expansion
    assertTrue(poolPriceAboveAfter, "Pool price should still be above oracle");
    assertLt(priceDiffAfter, priceDiffBefore, "Price should improve");
    assertGt(priceDiffAfter, 500, "Price should be at rebalance threshold");
    assertEq(stabilityPoolDebtBefore - (reserve0After - reserve0Before), stabilityPoolDebtAfter);
    // 25 bps of the expansion amount is taken as protocol incentive
    assertEq(
      stabilityPoolCollBefore + (reserve1Before - reserve1After) - (((reserve1Before - reserve1After) * 25) / 10_000),
      stabilityPoolCollAfter
    );
    assertGt(reserve0After, reserve0Before, "Debt reserves should increase");
    assertLt(reserve1After, reserve1Before, "Collateral reserves should decrease");
    assertEq(stabilityPoolDebtAfter, 1e18, "Stability pool should be at minimum");
    assertReserveValueIncentives(reserve0Before, reserve1Before, reserve0After, reserve1After);
    assertRebalanceAmountIncentives(reserve1Before - reserve1After, reserve0After - reserve0Before, false);
    assertIncentive(
      reserve1Before - reserve1After,
      protocolFeeRecipientBalanceAfter - protocolFeeRecipientBalanceBefore,
      25
    );
  }

  /* ============================================================ */
  /* ============== Expansion Token 1 Debt Tests =============== */
  /* ============================================================ */

  function test_rebalance_whenToken1DebtPoolPriceBelowAndEnoughFundsinStabilityPool_shouldExpandToRebalanceThreshold()
    public
    fpmmToken1Debt(18, 6)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // USDC/USD rate
    uint256 oracleNum = 999884980000000000;
    uint256 oracleDen = 1e18;

    // Setup
    provideFPMMReserves(10_000e6, 10_000e18, false);
    setOracleRate(oracleNum, oracleDen);

    // Debalance FPMM by swapping 5k USDC into the pool
    swapIn(collToken, 5_000e6);

    // Set stability pool balance high enough
    setStabilityPoolBalance(debtToken, 100_000e18);
    setMockSystemParamsMinBoldAfterRebalance(1e18);

    // Snapshot before rebalance
    (, , , , bool poolPriceAboveBefore, , uint256 priceDiffBefore) = fpmm.getRebalancingState();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 stabilityPoolDebtBefore = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBefore = IERC20(collToken).balanceOf(address(mockStabilityPool));

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , bool poolPriceAboveAfter, , uint256 priceDiffAfter) = fpmm.getRebalancingState();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 stabilityPoolDebtAfter = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollAfter = IERC20(collToken).balanceOf(address(mockStabilityPool));

    // Verify results
    assertFalse(poolPriceAboveAfter, "Pool price should still be below oracle");
    assertEq(priceDiffAfter, 500, "Price difference should be at rebalance threshold");
    assertEq(
      stabilityPoolDebtAfter,
      stabilityPoolDebtBefore - (reserve1After - reserve1Before),
      "Stability pool debt should decrease"
    );
    // 25 bps of the expansion amount is taken as protocol incentive
    assertEq(
      stabilityPoolCollAfter,
      stabilityPoolCollBefore + (reserve0Before - reserve0After) - (((reserve0Before - reserve0After) * 25) / 10_000),
      "Stability pool collateral should increase"
    );
    assertLt(reserve0After, reserve0Before, "Collateral reserves should decrease");
    assertGt(reserve1After, reserve1Before, "Debt reserves should increase");
    assertReserveValueIncentives(reserve0Before, reserve1Before, reserve0After, reserve1After);
    assertRebalanceAmountIncentives(reserve0Before - reserve0After, reserve1After - reserve1Before, true);
  }

  function test_rebalance_whenToken1DebtPoolPriceBelowAndNotEnoughFundsInStabilityPool_shouldExpandAndBringPriceCloserToRebalanceThreshold()
    public
    fpmmToken1Debt(18, 6)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // USDC/USD rate
    uint256 oracleNum = 999884980000000000;
    uint256 oracleDen = 1e18;

    // Setup
    provideFPMMReserves(100_000e6, 100_000e18, false);
    setOracleRate(oracleNum, oracleDen);

    // Debalance FPMM by swapping 5k USDC into the pool
    swapIn(collToken, 30_000e6);

    // Set stability pool balance to less than full expansion
    setStabilityPoolBalance(debtToken, 20_000e18);
    setMockSystemParamsMinBoldAfterRebalance(1e18);

    // Snapshot before rebalance
    (, , , , bool poolPriceAboveBefore, , uint256 priceDiffBefore) = fpmm.getRebalancingState();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 stabilityPoolDebtBefore = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBefore = IERC20(collToken).balanceOf(address(mockStabilityPool));

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, address(0), 0, address(0), 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , bool poolPriceAboveAfter, , uint256 priceDiffAfter) = fpmm.getRebalancingState();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 stabilityPoolDebtAfter = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollAfter = IERC20(collToken).balanceOf(address(mockStabilityPool));

    // Verify results
    assertFalse(poolPriceAboveAfter, "Pool price should still be below oracle");
    assertLt(priceDiffAfter, priceDiffBefore, "Price difference should be less than before");
    assertEq(
      stabilityPoolDebtAfter,
      stabilityPoolDebtBefore - (reserve1After - reserve1Before),
      "Stability pool debt should decrease"
    );
    // 25 bps of the expansion amount is taken as protocol incentive
    assertEq(
      stabilityPoolCollAfter,
      stabilityPoolCollBefore + (reserve0Before - reserve0After) - (((reserve0Before - reserve0After) * 25) / 10_000),
      "Stability pool collateral should increase"
    );
    assertLt(reserve0After, reserve0Before, "Collateral reserves should decrease");
    assertGt(reserve1After, reserve1Before, "Debt reserves should increase");
    assertReserveValueIncentives(reserve0Before, reserve1Before, reserve0After, reserve1After);
    assertRebalanceAmountIncentives(reserve0Before - reserve0After, reserve1After - reserve1Before, true);
  }

  /* ============================================================ */
  /* ========== Redemption Rounding Edge Case Tests ============= */
  /* ============================================================ */

  function test_rebalance_whenRedemptionShortfallExceedsTolerance_shouldRevert()
    public
    fpmmToken0Debt(12, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // COP/USD rate: 1 USD = ~3920 COP
    uint256 oracleNum = 255050000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide initial reserves
    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNum, oracleDen);
    mockCollateralRegistryOracleRate(oracleNum, oracleDen);

    // Debalance FPMM to trigger contraction
    swapIn(debtToken, 784_150_001e12);

    // Set shortfall to exceed tolerance (1e5)
    mockCollateralRegistry.setRedemptionShortfall(1e6);

    // Should revert with CDPLS_REDEMPTION_SHORTFALL_TOO_LARGE (exact shortfall depends on calculation)
    vm.expectPartialRevert(ICDPLiquidityStrategy.CDPLS_REDEMPTION_SHORTFALL_TOO_LARGE.selector);
    strategy.rebalance(address(fpmm));
  }

  function test_rebalance_whenRedemptionShortfallWithinToleranceAndEnoughFunds_shouldSucceed()
    public
    fpmmToken0Debt(12, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // COP/USD rate: 1 USD = ~3920 COP
    uint256 oracleNum = 255050000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide initial reserves
    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNum, oracleDen);
    mockCollateralRegistryOracleRate(oracleNum, oracleDen);

    // Debalance FPMM to trigger contraction
    swapIn(debtToken, 784_150_001e12);

    // Set shortfall within tolerance (1e5)
    mockCollateralRegistry.setRedemptionShortfall(1e4);

    uint256 reserve1Before = fpmm.reserve1();

    // Expect the RedemptionShortfallSubsidized event
    // Shortfall is 9465 (not 1e4) due to fee calculations affecting the redemption amount
    vm.expectEmit(true, true, true, true);
    emit ICDPLiquidityStrategy.RedemptionShortfallSubsidized(address(fpmm), 9465);

    // Should succeed
    strategy.rebalance(address(fpmm));

    uint256 reserve1After = fpmm.reserve1();
    // Verify that collateral was added to the pool
    assertGt(reserve1After, reserve1Before, "Collateral reserves should increase");
  }

  function test_rebalance_whenRedemptionShortfallWithinToleranceButNotEnoughFunds_shouldRevert()
    public
    fpmmToken0Debt(12, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    // COP/USD rate: 1 USD = ~3920 COP
    uint256 oracleNum = 255050000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide initial reserves
    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNum, oracleDen);
    mockCollateralRegistryOracleRate(oracleNum, oracleDen);

    // Debalance FPMM to trigger contraction
    swapIn(debtToken, 784_150_001e12);

    // Set shortfall within tolerance
    mockCollateralRegistry.setRedemptionShortfall(1e4);

    // Drain the strategy's collateral balance so it can't subsidize
    uint256 strategyCollBalance = IERC20(collToken).balanceOf(address(strategy));
    vm.prank(address(strategy));
    IERC20(collToken).transfer(address(1), strategyCollBalance);

    // Should revert with CDPLS_OUT_OF_FUNDS_FOR_REDEMPTION_SUBSIDY
    vm.expectRevert(ICDPLiquidityStrategy.CDPLS_OUT_OF_FUNDS_FOR_REDEMPTION_SUBSIDY.selector);
    strategy.rebalance(address(fpmm));
  }
}
