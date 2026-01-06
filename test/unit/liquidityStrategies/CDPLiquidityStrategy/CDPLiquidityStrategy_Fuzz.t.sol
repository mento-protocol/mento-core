// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, max-line-length
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy_FuzzTest is CDPLiquidityStrategy_BaseTest {
  LQ.Context public ctx;

  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Fuzz Test Helpers ======================== */
  /* ============================================================ */
  /**
   * @notice Bounds the fuzz parameters for the test
   * @param oracleNumerator The oracle numerator
   * @param reserve0 The reserve0
   * @param reserve1 The reserve1
   * @param poolPriceAbove The pool price above
   */
  modifier _boundFuzzParams(uint256 oracleNumerator, uint256 reserve0, uint256 reserve1, bool poolPriceAbove) {
    // price range from 0.001 to 100_000
    oracleNumerator = bound(oracleNumerator, 1e15, 1e23);
    uint256 oracleDenominator = 1e18;
    reserve0 = bound(reserve0, 100e18, 100_000_000e18);

    if (poolPriceAbove) {
      uint256 reserve1LowerBound = (reserve0 * oracleNumerator * 111) / (oracleDenominator * 100);
      reserve1 = bound(reserve1, reserve1LowerBound, reserve1LowerBound * 5);
    } else {
      uint256 reserve1UpperBound = (reserve0 * oracleNumerator * 89) / (oracleDenominator * 100);

      reserve1 = bound(reserve1, (reserve1UpperBound * 1) / 5, reserve1UpperBound);
    }

    ctx.reserves = LQ.Reserves({ reserveNum: reserve1, reserveDen: reserve0 });

    ctx.prices = LQ.Prices({
      oracleNum: oracleNumerator,
      oracleDen: oracleDenominator,
      poolPriceAbove: poolPriceAbove,
      diffBps: 200
    });
    _;
  }

  /* ---------- Determine Action Fuzz Tests ---------- */

  struct FuzzTestContext {
    uint256 stabilityPoolBalance;
    uint256 priceDifferenceBefore;
    uint256 priceDifferenceAfter;
    uint256 reserve0After;
    uint256 reserve1After;
    bool reservePriceAboveOraclePriceBefore;
    bool reservePriceAboveOraclePriceAfter;
  }

  /* ============================================================ */
  /* ================ Expansion Full liquidity ================== */
  /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceAboveAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(18, 18) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = debtToken;
    ctx.token1 = collToken;
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    // enough to cover the full expansion
    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(1e18, ctx);
    setStabilityPoolBalance(debtToken, testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertTrue(testContext.reservePriceAboveOraclePriceBefore);
    assertTrue(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand);
    assertEq(action.amount0Out, 0);
    assertGt(action.amount1Out, 0);
    assertGt(action.amountOwedToPool, 0);

    testContext.reserve0After = ctx.reserves.reserveDen + action.amountOwedToPool;
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assertEq(testContext.priceDifferenceAfter, 0, "Price difference should be zero");
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceBelowAndEnoughLiquidityInStabilityPool_shouldExpandAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(18, 6) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;
    ctx.pool = address(fpmm);
    ctx.token0 = collToken;
    ctx.token1 = debtToken;
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(1e18, ctx);
    setStabilityPoolBalance(debtToken, testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertFalse(testContext.reservePriceAboveOraclePriceBefore);
    assertGt(testContext.priceDifferenceBefore, 999); // at least 10% above the oracle price

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand);
    assertGt(action.amount0Out, 0);
    assertEq(action.amount1Out, 0);
    assertGt(action.amountOwedToPool, 0);

    testContext.reserve0After = ctx.reserves.reserveDen - (action.amount0Out * 1e18) / ctx.token0Dec;
    testContext.reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assertEq(testContext.priceDifferenceAfter, 0, "Price difference should be zero");
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out * (1e18 / ctx.token0Dec),
      action.amountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  // /* ============================================================ */
  // /* ============== Expansion Partial liquidity ================= */
  // /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceAboveAndLimitedLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(6, 18) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = debtToken;
    ctx.token1 = collToken;
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    // enough to cover the full expansion
    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.9e18, ctx); // stability pool holds 90% of target amount to rebalance fully
    setStabilityPoolBalance(debtToken, testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assert(testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand);
    assertEq(action.amount0Out, 0);
    assertGt(action.amount1Out, 0);
    assertGt(action.amountOwedToPool, 0);

    testContext.reserve0After = ctx.reserves.reserveDen + action.amountOwedToPool * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    // price difference should be greater than 0
    assertLt(testContext.priceDifferenceAfter, testContext.priceDifferenceBefore);
    assertGt(testContext.priceDifferenceAfter, 0);
    // reserve price should be still above oracle price
    assertTrue(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.amountOwedToPool * (1e18 / ctx.token0Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceBelowAndLimitedLiquidityInStabilityPool_shouldExpandAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(6, 18) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;
    ctx.pool = address(fpmm);
    ctx.token0 = collToken;
    ctx.token1 = debtToken;
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    testContext.stabilityPoolBalance = calculateTargetStabilityPoolBalance(0.8e18, ctx); // stability pool holds 90% of target amount to rebalance fully
    setStabilityPoolBalance(debtToken, testContext.stabilityPoolBalance);

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assert(!testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand);
    assertGt(action.amount0Out, 0);
    assertEq(action.amount1Out, 0);
    assertGt(action.amountOwedToPool, 0);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    testContext.reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    // price difference should be less than before
    assertLt(testContext.priceDifferenceAfter, testContext.priceDifferenceBefore);
    assertGt(testContext.priceDifferenceAfter, 0);
    // reserve price should still be below oracle price
    assertFalse(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      action.amountOwedToPool * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  // /* ============================================================ */
  // /* =============== Contraction target liquidity =============== */
  // /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceBelowAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(18, 6) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = debtToken;
    ctx.token1 = collToken;
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertFalse(testContext.reservePriceAboveOraclePriceBefore);
    assertGt(testContext.priceDifferenceBefore, 999); // at least 10% above the oracle price

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    // ensure redemption fractions is below 0.25% resulting in total redemption fee less than 0.5%
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18, ctx);
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract);
    assertGt(action.amount0Out, 0);
    assertEq(action.amount1Out, 0);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption

    // this value can be off by a few wei due to rounding errors from calculating expected collateral received from redemption.
    uint256 expectedCollateralReceived = calculatedExpectedCollateralReceivedFromRedemption(action.amount0Out, ctx);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    testContext.reserve1After = ctx.reserves.reserveNum + expectedCollateralReceived * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );

    // price difference should be near zero (allowing small tolerance due to REDEMPTION_ROUNDING_BUFFER)
    // The buffer impact can vary based on reserve sizes in fuzz tests
    assertLe(testContext.priceDifferenceAfter, 200, "Price difference should be near zero");
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      expectedCollateralReceived * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceAboveAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken1Debt(6, 18) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = collToken;
    ctx.token1 = debtToken;
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assert(testContext.reservePriceAboveOraclePriceBefore);
    assert(testContext.priceDifferenceBefore >= 999); // at least 10% above the oracle price

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18, ctx);
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);
    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, 0);
    assertGt(action.amount1Out, 0);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption

    // this value can be off by a few wei due to rounding errors from calculating expected collateral received from redemption.
    uint256 expectedCollateralReceived = calculatedExpectedCollateralReceivedFromRedemption(action.amount1Out, ctx);

    testContext.reserve0After = ctx.reserves.reserveDen + expectedCollateralReceived;
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    // price difference should be near zero (allowing small tolerance due to REDEMPTION_ROUNDING_BUFFER)
    // The buffer impact can vary based on reserve sizes in fuzz tests
    assertLe(testContext.priceDifferenceAfter, 200, "Price difference should be near zero");
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out * (1e18 / ctx.token1Dec),
      expectedCollateralReceived,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  // /* ============================================================ */
  // /* ============== Contraction non-target liquidity ============ */
  // /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceBelowAndRedemptionFeeLessIncentive_shouldContractAndBringPriceAboveOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(18, 6) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = debtToken;
    ctx.token1 = collToken;
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertFalse(testContext.reservePriceAboveOraclePriceBefore);
    assertGt(testContext.priceDifferenceBefore, 999); // at least 10% above the oracle price

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.001 * 1e18, ctx); // 0.1% resulting in redemption fee beeing 0.25% + 0.1% = 0.35%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract));
    assertGt(action.amount0Out, 0);
    assertEq(action.amount1Out, 0);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption

    // this value can be off by a few wei due to rounding errors from calculating expected collateral received from redemption.
    uint256 expectedCollateralReceived = calculatedExpectedCollateralReceivedFromRedemption(action.amount0Out, ctx);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    testContext.reserve1After = ctx.reserves.reserveNum + expectedCollateralReceived * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assertGe(testContext.priceDifferenceAfter, 0, "Price difference should be greater than or equal to zero");
    assertTrue(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      expectedCollateralReceived * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      true
    );
  }

  // /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken0DebtPoolPriceBelowAndRedemptionFeeMoreThanIncentive_shouldContractAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(6, 18) _boundFuzzParams(oracleNumerator, reserve0, reserve1, false) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = debtToken;
    ctx.token1 = collToken;
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = true;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertFalse(testContext.reservePriceAboveOraclePriceBefore);
    assertGt(testContext.priceDifferenceBefore, 999); // at least 10% above the oracle price

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.003 * 1e18, ctx); // 0.3% resulting in redemption fee beeing 0.25% + 0.3% = 0.55%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);
    assertEq(action.dir, LQ.Direction.Contract);
    assertGt(action.amount0Out, 0);
    assertEq(action.amount1Out, 0);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption

    // this value can be off by a few wei due to rounding errors from calculating expected collateral received from redemption.
    uint256 expectedCollateralReceived = calculatedExpectedCollateralReceivedFromRedemption(action.amount0Out, ctx);

    testContext.reserve0After = ctx.reserves.reserveDen - action.amount0Out * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum + expectedCollateralReceived;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );

    assertGe(testContext.priceDifferenceAfter, 0, "Price difference should be greater than or equal to zero");
    assertFalse(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out * (1e18 / ctx.token0Dec),
      expectedCollateralReceived,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }

  /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceAboveAndRedemptionFeeLessIncentive_shouldContractAndBringPriceBelowOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken1Debt(6, 18) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = collToken;
    ctx.token1 = debtToken;
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertTrue(testContext.reservePriceAboveOraclePriceBefore);
    assertGt(testContext.priceDifferenceBefore, 999); // at least 10% above the oracle price

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.001 * 1e18, ctx); // 0.1% resulting in redemption fee beeing 0.25% + 0.1% = 0.35%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);
    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, 0);
    assertGt(action.amount1Out, 0);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption

    // this value can be off by a few wei due to rounding errors from calculating expected collateral received from redemption.
    uint256 expectedCollateralReceived = calculatedExpectedCollateralReceivedFromRedemption(action.amount1Out, ctx);

    testContext.reserve0After = ctx.reserves.reserveDen + expectedCollateralReceived * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assertGe(testContext.priceDifferenceAfter, 0, "Price difference should be greater than or equal to zero");
    assertFalse(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      expectedCollateralReceived * (1e18 / ctx.token0Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      true
    );
  }

  // /// forge-config: default.fuzz.runs = 10000
  function test_FUZZ_whenToken1DebtPoolPriceAboveAndRedemptionFeeMoreThanIncentive_shouldContractAndBringPriceCloserToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken1Debt(6, 18) _boundFuzzParams(oracleNumerator, reserve0, reserve1, true) addFpmm(0, 50, 9000) {
    FuzzTestContext memory testContext;

    ctx.pool = address(fpmm);
    ctx.token0 = collToken;
    ctx.token1 = debtToken;
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.isToken0Debt = false;
    ctx.incentiveBps = 50;

    (testContext.priceDifferenceBefore, testContext.reservePriceAboveOraclePriceBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );

    assertTrue(testContext.reservePriceAboveOraclePriceBefore);
    assertGt(testContext.priceDifferenceBefore, 999); // at least 10% above the oracle price

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.003 * 1e18, ctx); // 0.3% resulting in redemption fee beeing 0.25% + 0.3% = 0.55%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);
    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, 0);
    assertGt(action.amount1Out, 0);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption

    // this value can be off by a few wei due to rounding errors from calculating expected collateral received from redemption.
    uint256 expectedCollateralReceived = calculatedExpectedCollateralReceivedFromRedemption(action.amount1Out, ctx);

    testContext.reserve0After = ctx.reserves.reserveDen + expectedCollateralReceived * (1e18 / ctx.token0Dec);
    testContext.reserve1After = ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec);

    (testContext.priceDifferenceAfter, testContext.reservePriceAboveOraclePriceAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      testContext.reserve1After,
      testContext.reserve0After
    );
    assertLt(testContext.priceDifferenceAfter, testContext.priceDifferenceBefore);
    assertTrue(testContext.reservePriceAboveOraclePriceAfter);
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      expectedCollateralReceived * (1e18 / ctx.token0Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      false
    );
  }
}
