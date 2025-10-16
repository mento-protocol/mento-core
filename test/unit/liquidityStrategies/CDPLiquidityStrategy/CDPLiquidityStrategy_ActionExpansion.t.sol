// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
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
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 1_000_000e18, // token0 (debt) reserves
      reserveNum: 1_500_000e18, // token1 (collateral) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50,
      isToken0Debt: true
    });

    // Set stability pool balance high enough to cover full expansion
    setStabilityPoolMinBalance(1e18);
    uint256 requiredBalance = calculateTargetStabilityPoolBalance(1e18, ctx);
    setStabilityPoolBalance(debtToken, requiredBalance);

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
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 1_000_000e18, // token0 (debt) reserves
      reserveNum: 1_500_000e18, // token1 (collateral) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50,
      isToken0Debt: true
    });

    setStabilityPoolMinBalance(1e18);
    // Set stability pool balance lower than what's needed for full expansion
    uint256 limitedBalance = calculateTargetStabilityPoolBalance(0.6e18, ctx);
    setStabilityPoolBalance(debtToken, limitedBalance);

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
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm

    // Setup: Pool price below oracle (excess collateral scenario for token1 debt)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50,
      isToken0Debt: false
    });

    // Set stability pool balance high enough to cover full expansion
    setStabilityPoolMinBalance(1e6);
    uint256 requiredBalance = calculateTargetStabilityPoolBalance(1e18, ctx);
    setStabilityPoolBalance(debtToken, requiredBalance);

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
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool * 1e12;

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
      action.amount0Out,
      action.amountOwedToPool * 1e12,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  function test_determineAction_whenToken1DebtPoolPriceBelowAndInsufficientLiquidity_shouldExpandPartially()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50,
      isToken0Debt: false
    });
    setStabilityPoolMinBalance(1e6);
    uint256 limitedBalance = calculateTargetStabilityPoolBalance(0.6e18, ctx);
    setStabilityPoolBalance(debtToken, limitedBalance);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen * 1e12 // normalize to 18 decimals
    );

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand");
    assertGt(action.amount0Out, 0, "Collateral (token0) should flow out during expansion");
    assertEq(action.amount1Out, 0, "No debt (token1) should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in via inputAmount");

    // Calculate reserves after action (normalize decimals for comparison)
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool * 1e12;

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

  /* ---------- Determine Action Math Tests ---------- */

  /* ============================================================ */
  /* ================ Expansion Full liquidity ================== */
  /* ============================================================ */

  function test_whenToken0DebtPoolPriceAboveAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 1_000_000e18,
      reserveNum: 1_500_000e18,
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50,
      isToken0Debt: true
    });

    // enough to cover the full expansion
    setStabilityPoolBalance(debtToken, 1_000_000e18);
    LQ.Action memory action = strategy.determineAction(ctx);

    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 250684.220551
    uint256 expectedAmount1Out = 250684220551;
    uint256 expectedAmount0Out = 0;
    // input amount in token 0 := (amountOut * OD * (1-i))/ON = 249459.492279046935978576
    uint256 expectedAmountOwedToPool = 249459492279046935978576;

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
  }

  function test_whenToken1DebtPoolPriceBelowAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 863549230000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50,
      isToken0Debt: false
    });

    // enough to cover the full expansion
    setStabilityPoolBalance(debtToken, 1_000_000 * 1e6);
    LQ.Action memory action = strategy.determineAction(ctx);

    // amount out in token 0 := (ON*RD-OD*RN)/(ON*(2-i)) = 71172.145133890686084197
    uint256 expectedAmount0Out = 71172145133890686084197;
    uint256 expectedAmount1Out = 0;
    // input amount in token 1 := (amountOut * ON * (1-i))/OD = 61153.347872

    uint256 expectedAmountOwedToPool = 61153347872;

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
  }

  /* ============================================================ */
  /* ============== Expansion Partial liquidity ================= */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceAboveAndNotEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToOraclePrice()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 999884980000000000, // USDC/USD rate
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50,
      isToken0Debt: true
    });

    // enough to cover 90% of the target amount
    uint256 stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.9e18, ctx);
    setStabilityPoolBalance(debtToken, stabilityPoolBalance);
    LQ.Action memory action = strategy.determineAction(ctx);

    (uint256 priceDiffBefore, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand");
    assertEq(action.amount0Out, 0, "No debt should flow out");
    assertGt(action.amount1Out, 0, "Collateral should flow out");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen + action.amountOwedToPool;
    uint256 reserve1After = ctx.reserves.reserveNum - action.amount1Out * 1e12;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    assertLt(priceDiffAfter, priceDiffBefore, "Price difference should decrease");
    assertGt(priceDiffAfter, 0, "Price difference should still be positive (partial expansion)");
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
