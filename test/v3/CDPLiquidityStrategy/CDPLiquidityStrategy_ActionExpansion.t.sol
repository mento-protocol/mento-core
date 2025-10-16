// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy_ActionExpansionTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ============= Expansion Token 0 Debt Tests ================ */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceAboveAndEnoughLiquidity_shouldExpandToOraclePrice()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Pool price above oracle (excess collateral scenario for token0 debt)
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_000_000e18, // token0 (debt) reserves
      reserveNum: 1_500_000e18, // token1 (collateral) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50 // 0.5%
    });

    // Set stability pool balance high enough to cover full expansion
    uint256 requiredBalance = 1e18 + (ctx.reserves.reserveNum * ctx.prices.oracleDen) / ctx.prices.oracleNum;
    setStabilityPoolBalance(debtToken, requiredBalance);
    setStabilityPoolMinBalance(1e18);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertEq(action.amount0Out, 0, "No debt should flow out during expansion");
    assertGt(action.amount1Out, 0, "Collateral should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in via inputAmount");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen + action.amountOwedToPool;
    uint256 reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    assertEq(priceDiffAfter, 0, "Price difference should be zero after expansion");
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  function test_determineAction_whenToken0DebtPoolPriceAboveAndInsufficientLiquidity_shouldExpandPartially()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Pool price above oracle but stability pool has limited funds
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_000_000e18, // token0 (debt) reserves
      reserveNum: 1_500_000e18, // token1 (collateral) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50
    });

    // Set stability pool balance lower than what's needed for full expansion
    uint256 limitedBalance = 100_000e18;
    setStabilityPoolBalance(debtToken, limitedBalance);
    setStabilityPoolMinBalance(1e18);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertGt(action.amount1Out, 0, "Collateral should flow out");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen + action.amountOwedToPool;
    uint256 reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    // Price should improve but not reach zero due to limited liquidity
    assertLt(priceDiffAfter, priceDiffBefore, "Price difference should decrease");
    assertGt(priceDiffAfter, 0, "Price difference should still be positive (partial expansion)");
  }

  /* ============================================================ */
  /* ============= Expansion Token 1 Debt Tests ================= */
  /* ============================================================ */

  function test_determineAction_whenToken1DebtPoolPriceBelowAndEnoughLiquidity_shouldExpandToOraclePrice()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Pool price below oracle (excess collateral scenario for token1 debt)
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 1_000_000e6, // token0 (collateral) reserves (6 decimals)
      reserveNum: 1_500_000e18, // token1 (debt) reserves (18 decimals)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50,
      token0Dec: 1e6,
      token1Dec: 1e18
    });

    ctx.isToken0Debt = false;
    ctx.token0 = collToken;
    ctx.token1 = debtToken;

    // Set stability pool balance high enough to cover full expansion
    uint256 requiredBalance = 1e18 + (ctx.reserves.reserveDen * 1e12 * ctx.prices.oracleNum) / ctx.prices.oracleDen;
    setStabilityPoolBalance(debtToken, requiredBalance);
    setStabilityPoolMinBalance(1e18);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen * 1e12 // normalize to 18 decimals
    );

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertGt(action.amount0Out, 0, "Collateral (token0) should flow out during expansion");
    assertEq(action.amount1Out, 0, "No debt (token1) should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in via inputAmount");

    // Calculate reserves after action (normalize decimals for comparison)
    uint256 reserve0After = ctx.reserves.reserveDen * 1e12 - action.amount0Out * 1e12;
    uint256 reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    assertEq(priceDiffAfter, 0, "Price difference should be zero after expansion");
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out * 1e12,
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  /* ============================================================ */
  /* ================ Stability Pool Edge Cases ================ */
  /* ============================================================ */

  function test_determineAction_whenStabilityPoolAtMinimum_shouldNotExpand()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Pool needs expansion but stability pool is at minimum
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_000_000e18,
      reserveNum: 1_500_000e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50
    });

    // Set stability pool balance exactly at minimum
    uint256 minBalance = 1000e18;
    setStabilityPoolBalance(debtToken, minBalance);
    setStabilityPoolMinBalance(minBalance);

    // Should revert when trying to determine action
    vm.expectRevert();
    strategy.determineAction(ctx);
  }

  function test_determineAction_whenStabilityPoolPercentageLimitsExpansion_shouldExpandToLimit()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 5000) // 50% stability pool percentage
  {
    // Setup: Large stability pool but limited by percentage
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_000_000e18,
      reserveNum: 1_500_000e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50
    });

    // Set large stability pool balance
    setStabilityPoolBalance(debtToken, 10_000_000e18);
    setStabilityPoolMinBalance(1e18);

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");

    // The expansion should be limited by the 50% stability pool percentage
    uint256 maxAllowed = (10_000_000e18 * 5000) / 10_000;
    assertLe(action.amountOwedToPool, maxAllowed, "Expansion should respect stability pool percentage limit");
  }

  /* ============================================================ */
  /* ================ Specific Scenario Tests =================== */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceAboveWith50PercentDifference_shouldExpandCorrectly()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    // Specific scenario: 1M USDFX (debt) and 1.5M USDC (collateral)
    // Pool price is 50% above oracle price (major imbalance)
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 1_000_000e18, // token0 (debt) reserves
      reserveNum: 1_500_000e6, // token1 (collateral) reserves (6 decimals)
      oracleNum: 999884980000000000, // ~1.0 USD/USDC
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50, // 0.5%
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    // Set stability pool balance high enough to cover full expansion
    setStabilityPoolBalance(debtToken, 1_000_000e18);
    setStabilityPoolMinBalance(1e18);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum * 1e12, // normalize to 18 decimals
      ctx.reserves.reserveDen
    );

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 4900, "Price difference should be close to 50%");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertEq(action.amount0Out, 0, "No debt should flow out");
    assertGt(action.amount1Out, 0, "Collateral should flow out");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen + action.amountOwedToPool;
    uint256 reserve1After = ctx.reserves.reserveNum * 1e12 - action.amount1Out * 1e12;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    assertEq(priceDiffAfter, 0, "Price should reach oracle after expansion");
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out * 1e12,
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }
}
