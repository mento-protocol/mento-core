// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract CDPLiquidityStrategy_RebalanceTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ============ Contraction Token 0 Debt Tests =============== */
  /* ============================================================ */

  function test_rebalance_whenToken0DebtPoolPriceBelowAndRedemptionFeeSmall_shouldContractToOraclePrice()
    public
    fpmmToken0Debt(12, 18)
    addFpmm(0, 50, 9000)
  {
    // COP/USD rate: 1 USD = ~3920 COP
    uint256 oracleNum = 255050000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide initial reserves (3.9M COP and 1M USD)
    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNum, oracleDen);

    // Set redemption parameters
    uint256 baseRate = 25e14; // 0.25%
    uint256 totalSupply = 1_000_000_000_000e12;
    mockRedemptionRateWithDecay(baseRate);
    setDebtTokenTotalSupply(totalSupply);
    mockCollateralRegistryOracleRate(oracleNum, oracleDen);

    // Debalance FPMM by swapping 200k USD worth of COP into the pool
    swapIn(debtToken, 784_150_001e12);

    // Snapshot before rebalance
    (, , , , uint256 priceDiffBefore, bool poolPriceAboveBefore) = fpmm.getPrices();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, 0, 0, 0);
    vm.expectEmit(true, false, false, false);
    emit RebalanceExecuted(address(fpmm), 0, 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , uint256 priceDiffAfter, bool poolPriceAboveAfter) = fpmm.getPrices();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();

    // Verify price improved significantly (within incentive tolerance)
    assertLe(priceDiffAfter, (priceDiffBefore * 50) / 10_000, "Price should improve to within incentive range");
    assertTrue(poolPriceAboveAfter, "Pool price should flip to above oracle");
    assertLt(reserve0After, reserve0Before, "Debt reserves should decrease");
    assertGt(reserve1After, reserve1Before, "Collateral reserves should increase");
  }

  function test_rebalance_whenToken0DebtPoolPriceBelowAndRedemptionFeeLarge_shouldContractPartially()
    public
    fpmmToken0Debt(12, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup with higher redemption fee constraint
    uint256 oracleNum = 255050000000000;
    uint256 oracleDen = 1e18;

    provideFPMMReserves(3_920_799_843e12, 1_000_000e18, true);
    setOracleRate(oracleNum, oracleDen);

    // Set redemption parameters with lower total supply (higher fee impact)
    uint256 baseRate = 25e14; // 0.25%
    uint256 totalSupply = 100_000_000_000e12; // Lower supply = higher redemption fraction fee
    mockRedemptionRateWithDecay(baseRate);
    setDebtTokenTotalSupply(totalSupply);
    mockCollateralRegistryOracleRate(oracleNum, oracleDen);

    // Debalance FPMM
    swapIn(debtToken, 784_150_001e12);

    // Snapshot before rebalance
    (, , , , uint256 priceDiffBefore, bool poolPriceAboveBefore) = fpmm.getPrices();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , uint256 priceDiffAfter, bool poolPriceAboveAfter) = fpmm.getPrices();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();

    // Verify partial contraction due to redemption fee limit
    assertLt(priceDiffAfter, priceDiffBefore, "Price should improve");
    assertFalse(poolPriceAboveAfter, "Pool price should still be below oracle (partial contraction)");
    assertLt(reserve0After, reserve0Before, "Debt reserves should decrease");
    assertGt(reserve1After, reserve1Before, "Collateral reserves should increase");

    // Verify contraction was limited by redemption fee
    uint256 maxRedeemable = (totalSupply * 25) / 10_000; // 0.25% of total supply
    assertEq(reserve0Before - reserve0After, maxRedeemable, "Should redeem exactly max allowed by fee");
  }

  /* ============================================================ */
  /* ============ Contraction Token 1 Debt Tests =============== */
  /* ============================================================ */

  function test_rebalance_whenToken1DebtPoolPriceAboveAndRedemptionFeeSmall_shouldContractToOraclePrice()
    public
    fpmmToken1Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    // USDC/USD rate (nearly 1:1)
    uint256 oracleNum = 999884980000000000;
    uint256 oracleDen = 1e18;

    // Setup: Provide initial reserves
    provideFPMMReserves(10_000e6, 10_000e18, false);
    setOracleRate(oracleNum, oracleDen);

    // Set redemption parameters
    uint256 baseRate = 25e14; // 0.25%
    uint256 totalSupply = 1e25;
    mockRedemptionRateWithDecay(baseRate);
    setDebtTokenTotalSupply(totalSupply);
    // For token1 debt, oracle rate is inverted
    mockCollateralRegistryOracleRate(oracleDen, oracleNum);

    // Debalance FPMM by swapping 5k USD into the pool
    swapIn(debtToken, 5_000e18);

    // Snapshot before rebalance
    (, , , , uint256 priceDiffBefore, bool poolPriceAboveBefore) = fpmm.getPrices();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Contract, 0, 0, 0);
    vm.expectEmit(true, false, false, false);
    emit RebalanceExecuted(address(fpmm), 0, 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , uint256 priceDiffAfter, bool poolPriceAboveAfter) = fpmm.getPrices();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();

    // Verify price improved significantly
    assertLe(priceDiffAfter, (priceDiffBefore * 50) / 10_000, "Price should improve to within incentive range");
    assertFalse(poolPriceAboveAfter, "Pool price should flip to below oracle");
    assertGt(reserve0After, reserve0Before, "Collateral reserves should increase");
    assertLt(reserve1After, reserve1Before, "Debt reserves should decrease");
  }

  /* ============================================================ */
  /* ============== Expansion Token 0 Debt Tests =============== */
  /* ============================================================ */

  function test_rebalance_whenToken0DebtPoolPriceAboveAndEnoughStabilityPool_shouldExpandToOraclePrice()
    public
    fpmmToken0Debt(12, 6)
    addFpmm(0, 50, 9000)
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
    setStabilityPoolMinBalance(1e18);

    // Snapshot before rebalance
    (, , , , uint256 priceDiffBefore, bool poolPriceAboveBefore) = fpmm.getPrices();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 stabilityPoolDebtBefore = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBefore = IERC20(collToken).balanceOf(address(mockStabilityPool));

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, 0, 0, 0);
    vm.expectEmit(true, false, false, false);
    emit RebalanceExecuted(address(fpmm), 0, 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , uint256 priceDiffAfter, bool poolPriceAboveAfter) = fpmm.getPrices();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 stabilityPoolDebtAfter = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollAfter = IERC20(collToken).balanceOf(address(mockStabilityPool));

    // Verify results
    assertTrue(poolPriceAboveAfter, "Pool price should still be above oracle");
    assertEq(priceDiffAfter, 0, "Price difference should be zero");
    assertEq(stabilityPoolDebtBefore - (reserve0After - reserve0Before), stabilityPoolDebtAfter, "Stability pool debt should decrease by expansion amount");
    assertEq(stabilityPoolCollBefore + (reserve1Before - reserve1After), stabilityPoolCollAfter, "Stability pool collateral should increase");
    assertGt(reserve0After, reserve0Before, "Debt reserves should increase");
    assertLt(reserve1After, reserve1Before, "Collateral reserves should decrease");
  }

  function test_rebalance_whenToken0DebtPoolPriceAboveAndLimitedStabilityPool_shouldExpandPartially()
    public
    fpmmToken0Debt(12, 6)
    addFpmm(0, 50, 9000)
  {
    // Setup similar to above but with limited stability pool
    uint256 oracleNum = 6755340000000000;
    uint256 oracleDen = 1e18;

    provideFPMMReserves(81_419_800e12, 550_000e6, true);
    setOracleRate(oracleNum, oracleDen);

    swapIn(collToken, 75_000e6);

    // Set stability pool balance insufficient for full expansion
    setStabilityPoolBalance(debtToken, 5_000_000e12);
    setStabilityPoolMinBalance(1e18);

    // Snapshot before rebalance
    (, , , , uint256 priceDiffBefore, bool poolPriceAboveBefore) = fpmm.getPrices();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 stabilityPoolDebtBefore = IERC20(debtToken).balanceOf(address(mockStabilityPool));

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , uint256 priceDiffAfter, bool poolPriceAboveAfter) = fpmm.getPrices();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 stabilityPoolDebtAfter = IERC20(debtToken).balanceOf(address(mockStabilityPool));

    // Verify partial expansion
    assertTrue(poolPriceAboveAfter, "Pool price should still be above oracle");
    assertLt(priceDiffAfter, priceDiffBefore, "Price should improve");
    assertGt(priceDiffAfter, 0, "Price should not reach zero (partial expansion)");
    assertGt(reserve0After, reserve0Before, "Debt reserves should increase");
    assertLt(reserve1After, reserve1Before, "Collateral reserves should decrease");
    assertEq(stabilityPoolDebtAfter, 1e18, "Stability pool should be at minimum");
  }

  /* ============================================================ */
  /* ============== Expansion Token 1 Debt Tests =============== */
  /* ============================================================ */

  function test_rebalance_whenToken1DebtPoolPriceBelowAndEnoughStabilityPool_shouldExpandToOraclePrice()
    public
    fpmmToken1Debt(18, 6)
    addFpmm(0, 50, 9000)
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
    setStabilityPoolMinBalance(1e18);

    // Snapshot before rebalance
    (, , , , uint256 priceDiffBefore, bool poolPriceAboveBefore) = fpmm.getPrices();
    uint256 reserve0Before = fpmm.reserve0();
    uint256 reserve1Before = fpmm.reserve1();
    uint256 stabilityPoolDebtBefore = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollBefore = IERC20(collToken).balanceOf(address(mockStabilityPool));

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    // Execute rebalance
    vm.expectEmit(true, true, false, false);
    emit LiquidityMoved(address(fpmm), LQ.Direction.Expand, 0, 0, 0);
    vm.expectEmit(true, false, false, false);
    emit RebalanceExecuted(address(fpmm), 0, 0);

    strategy.rebalance(address(fpmm));

    // Snapshot after rebalance
    (, , , , uint256 priceDiffAfter, bool poolPriceAboveAfter) = fpmm.getPrices();
    uint256 reserve0After = fpmm.reserve0();
    uint256 reserve1After = fpmm.reserve1();
    uint256 stabilityPoolDebtAfter = IERC20(debtToken).balanceOf(address(mockStabilityPool));
    uint256 stabilityPoolCollAfter = IERC20(collToken).balanceOf(address(mockStabilityPool));

    // Verify results
    assertFalse(poolPriceAboveAfter, "Pool price should still be below oracle");
    assertEq(priceDiffAfter, 0, "Price difference should be zero");
    assertEq(stabilityPoolDebtAfter, stabilityPoolDebtBefore - (reserve1After - reserve1Before), "Stability pool debt should decrease");
    assertEq(stabilityPoolCollAfter, stabilityPoolCollBefore + (reserve0Before - reserve0After), "Stability pool collateral should increase");
    assertLt(reserve0After, reserve0Before, "Collateral reserves should decrease");
    assertGt(reserve1After, reserve1Before, "Debt reserves should increase");
  }
}
