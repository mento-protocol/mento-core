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

  function test_determineAction_whenToken0DebtPoolPriceAboveAndEnoughLiquidity_shouldExpandToRebalanceThreshold()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
  {
    // Setup: Pool price above oracle (excess collateral scenario for token0 debt)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 1_000_000e18, // token0 (debt) reserves
      reserveNum: 1_500_000e18, // token1 (collateral) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      isToken0Debt: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    // Set stability pool balance high enough to cover full expansion
    setMockSystemParamsMinBoldAfterRebalance(1e18);
    uint256 requiredBalance = calculateTargetStabilityPoolBalance(1e18, ctx);
    setStabilityPoolBalance(debtToken, requiredBalance);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

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

    assertEq(priceDiffAfter, 500, "Price difference should be equal to rebalance threshold");
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
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
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
  {
    // Setup: Pool price above oracle but stability pool has limited funds
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 1_000_000e18, // token0 (debt) reserves
      reserveNum: 1_500_000e18, // token1 (collateral) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      isToken0Debt: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    setMockSystemParamsMinBoldAfterRebalance(1e18);
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
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

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
    assertGt(
      priceDiffAfter,
      500,
      "Price difference should still be greater than rebalance threshold (partial expansion)"
    );
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
      false,
      action.amount1Out,
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  /* ============================================================ */
  /* ============= Expansion Token 1 Debt Tests ================= */
  /* ============================================================ */

  function test_determineAction_whenToken1DebtPoolPriceBelowAndEnoughLiquidity_shouldExpandToRebalanceThreshold()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
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
      isToken0Debt: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    // Set stability pool balance high enough to cover full expansion
    setMockSystemParamsMinBoldAfterRebalance(1e6);
    uint256 requiredBalance = calculateTargetStabilityPoolBalance(1e18, ctx);
    setStabilityPoolBalance(debtToken, requiredBalance);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen * 1e12 // normalize to 18 decimals
    );

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertGt(action.amount0Out, 0, "Collateral (token0) should flow out during expansion");
    assertEq(action.amount1Out, 0, "No debt (token1) should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in via inputAmount");

    // Calculate reserves after action (normalize decimals for comparison)
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool * 1e12;

    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    assertEq(priceDiffAfter, 500, "Price difference should be at rebalance threshold after expansion");
    assertFalse(poolPriceAboveAfter, "Pool price should be still below oracle");
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
      true,
      action.amount0Out,
      (action.amountOwedToPool) * 1e12,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  function test_determineAction_whenToken1DebtPoolPriceBelowAndInsufficientLiquidity_shouldExpandPartially()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
  {
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      isToken0Debt: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });
    setMockSystemParamsMinBoldAfterRebalance(1e6);
    uint256 limitedBalance = calculateTargetStabilityPoolBalance(0.6e18, ctx);
    setStabilityPoolBalance(debtToken, limitedBalance);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen * 1e12 // normalize to 18 decimals
    );

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertGt(action.amount0Out, 0, "Collateral (token0) should flow out during expansion");
    assertEq(action.amount1Out, 0, "No debt (token1) should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in via inputAmount");

    // Calculate reserves after action (normalize decimals for comparison)
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool * 1e12;

    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    // Price should improve but not reach zero due to limited liquidity
    assertLt(priceDiffAfter, priceDiffBefore, "Price difference should decrease");
    assertFalse(poolPriceAboveAfter, "Pool price should be still below oracle");
    assertGt(
      priceDiffAfter,
      500,
      "Price difference should still be greater than rebalance threshold (partial expansion)"
    );
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
      true,
      action.amount0Out,
      action.amountOwedToPool * 1e12,
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
    addFpmm(0, 9000, 100, 0.002506265664160401e18, 0.0025e18, 0.0025e18, 0.0025e18)
  {
    // Setup: Pool needs expansion but stability pool is at minimum
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_000_000e18,
      reserveNum: 1_500_000e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    // Set stability pool balance exactly at minimum
    uint256 minBalance = 1000e18;
    setStabilityPoolBalance(debtToken, minBalance);
    setMockSystemParamsMinBoldAfterRebalance(minBalance);

    // Should revert when trying to determine action
    vm.expectRevert();
    strategy.determineAction(ctx);
  }

  function test_determineAction_whenStabilityPoolPercentageLimitsExpansion_shouldExpandToLimit()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 5000, 100, 0.002506265664160401e18, 0.0025e18, 0.0025e18, 0.0025e18) // 50% stability pool percentage
  {
    // Setup: Large stability pool but limited by percentage
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_000_000e18,
      reserveNum: 1_500_000e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    // Set large stability pool balance
    setStabilityPoolBalance(debtToken, 400_000e18);
    setMockSystemParamsMinBoldAfterRebalance(1e18);

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");

    // The expansion should be limited by the 50% stability pool percentage
    uint256 maxAllowed = (400_000e18 * 5000) / 10_000;
    assertEq(action.amountOwedToPool, maxAllowed, "Expansion should respect stability pool percentage limit");
  }

  /* ---------- Determine Action Math Tests ---------- */

  /* ============================================================ */
  /* ================ Expansion Full liquidity ================== */
  /* ============================================================ */

  function test_whenToken0DebtPoolPriceAboveAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToRebalanceThreshold()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
  {
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 1_000_000e18,
      reserveNum: 1_500_000e18,
      oracleNum: 999884980000000000,
      oracleDen: 1e18,
      poolPriceAbove: true,
      isToken0Debt: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    // enough to cover the full expansion
    setStabilityPoolBalance(debtToken, 1_000_000e18);
    LQ.Action memory action = strategy.determineAction(ctx);

    // amount out in token1 := (RN * TD - TN * RD) / (TD + TN * (1 - i) * OD/ON) = 220134.867832
    uint256 expectedAmount1Out = 220134867832;
    uint256 expectedAmount0Out = 0;
    // input amount in token 0 := (amountOut * OD * (1-i))/ON = 219059.389703843736106526
    uint256 expectedAmountOwedToPool = 219059389703843736106526;

    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec),
      ctx.reserves.reserveDen + action.amountOwedToPool
    );
    assertTrue(poolPriceAboveAfter, "Pool price should be above oracle");
    assertEq(priceDiffAfter, 500, "Price difference should be equal to rebalance threshold");

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
      false,
      action.amount1Out * (1e18 / ctx.token1Dec),
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  function test_whenToken1DebtPoolPriceBelowAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToRebalanceThreshold()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
  {
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 863549230000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      isToken0Debt: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    // enough to cover the full expansion
    setStabilityPoolBalance(debtToken, 1_000_000 * 1e6);
    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    LQ.Action memory action = strategy.determineAction(ctx);

    // amount out in token 0 := (TN * RD - RN * TD) / (TN + TD * (1 - i) * ON/OD) = 39582.740124479135597930
    uint256 expectedAmount0Out = 39582740124479135597930;
    uint256 expectedAmount1Out = 0;
    // input amount in token 1 := (amountOut * OD * (1-i))/ON = 34010.736532
    uint256 expectedAmountOwedToPool = 34010736532;

    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum + action.amountOwedToPool * (1e18 / ctx.token1Dec),
      ctx.reserves.reserveDen - action.amount0Out
    );
    assertFalse(poolPriceAboveAfter, "Pool price should be below oracle");
    assertEq(priceDiffAfter, 500, "Price difference should be equal to rebalance threshold");

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
      true,
      action.amount0Out,
      action.amountOwedToPool * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  /* ============================================================ */
  /* ============== Expansion Partial liquidity ================= */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceAboveAndNotEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToRebalanceThreshold()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
  {
    uint256 reserve0 = 1_000_000 * 1e18; // usdfx
    uint256 reserve1 = 1_500_000 * 1e6; // usdc

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 999884980000000000, // USDC/USD rate
      oracleDen: 1e18,
      poolPriceAbove: true,
      isToken0Debt: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    // enough to cover 90% of the target amount
    uint256 stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.9e18, ctx);
    setStabilityPoolBalance(debtToken, stabilityPoolBalance);
    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    LQ.Action memory action = strategy.determineAction(ctx);
    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec),
      ctx.reserves.reserveDen + action.amountOwedToPool
    );
    assertTrue(poolPriceAboveAfter, "Pool price should be above oracle");
    assertGt(priceDiffAfter, 500, "Price difference should be greater than rebalance threshold (partial expansion)");

    // target amount out in token1 := (RN * TD - TN * RD) / (TD + TN * (1 - i) * OD/ON) = 220134.867832
    // since we only have limited liquidity:
    // amount out in token1 := (197153450733459362495873 * ON * 1) / (OD * (1-i)) = 198121.381048
    uint256 expectedAmount1Out = 198121381048;
    uint256 expectedAmount0Out = 0;
    // target input amount in token 0 := (amountOut * OD * (1-i))/ON = 219059.389703843736106526
    // available stability pool balance = 219059389703843736106526 * 0.9 = 197153.450733459362495873
    uint256 expectedAmountOwedToPool = 197153450733459362495873;

    // since we only have liquidity for 90% of the target amount, the input amount should be 90% of the target amount
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
      false,
      action.amount1Out * (1e18 / ctx.token1Dec),
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  function test_determineAction_whenToken1DebtPoolPriceBelowAndNotEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToRebalanceThreshold()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 9000, 100, 0.0025e18, 0.0025e18, 0.002506265664160401e18, 0.0025e18)
  {
    uint256 reserve0 = 1_300_000 * 1e18; // usdm
    uint256 reserve1 = 1_000_000 * 1e6; // eurm

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 863549230000000000, // USD/EUR rate
      oracleDen: 1e18,
      poolPriceAbove: false,
      isToken0Debt: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
        protocolIncentiveExpansion: 0.0025e18,
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.0025e18
      })
    });

    // enough to cover 90% of the target amount
    uint256 stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.9e18, ctx);
    setStabilityPoolBalance(debtToken, stabilityPoolBalance);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    LQ.Action memory action = strategy.determineAction(ctx);

    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum + action.amountOwedToPool * (1e18 / ctx.token0Dec),
      ctx.reserves.reserveDen - action.amount0Out
    );
    assertFalse(poolPriceAboveAfter, "Pool price should be below oracle");
    assertGt(priceDiffAfter, 500, "Price difference should be greater than rebalance threshold (partial expansion)");

    // amount out in token 0 := (RN * TD - TN * RD) / (TD + TN * (1 - i) * OD/ON) = 39582.740124479135597930
    // since we only have limited liquidity:
    // amount out in token 0 := (30609.662878 * OD * 1) / (ON * (1-i)) = 35624.466111094772123904
    uint256 expectedAmount0Out = 35624466111094772123904;
    uint256 expectedAmount1Out = 0;
    // target input amount in token 1 := (amountOut * ON * (1-i))/OD = 34010.736532
    // available stability pool balance =  34010.736532 * 0.9 = 30609.662878
    uint256 expectedAmountOwedToPool = 30609662878;

    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
    assertIncentive(
      LQ.combineFees(ctx.incentives.liquiditySourceIncentiveExpansion, ctx.incentives.protocolIncentiveExpansion),
      true,
      action.amount0Out,
      action.amountOwedToPool * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }
}
