// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy_FuzzTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Fuzz Test Helpers ======================== */
  /* ============================================================ */

  modifier boundFuzzParams(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1,
    bool poolPriceAbove
  ) {
    // price range from 0.000001 to 100_000
    oracleNumerator = bound(oracleNumerator, 1e12, 1e23);
    uint256 oracleDenominator = 1e18;
    reserve0 = bound(reserve0, 100e18, 100_000_000e18);

    if (poolPriceAbove) {
      uint256 reserve1LowerBound = (reserve0 * oracleNumerator * 110) / (oracleDenominator * 100);
      reserve1 = bound(reserve1, reserve1LowerBound, reserve1LowerBound * 5);
    } else {
      uint256 reserve1UpperBound = (reserve0 * oracleNumerator * 90) / (oracleDenominator * 100);
      reserve1 = bound(reserve1, (reserve1UpperBound * 1) / 5, reserve1UpperBound);
    }
    _;
  }

  /* ============================================================ */
  /* ============== Expansion Fuzz Tests ======================== */
  /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_whenToken0DebtPoolPriceAboveAndEnoughLiquidity_shouldExpandToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(18, 18) addFpmm(0, 50, 9000) boundFuzzParams(oracleNumerator, reserve0, reserve1, true) {
    LQ.Context memory ctx;
    ctx.pool = address(fpmm);
    ctx.reserves = LQ.Reserves({ reserveNum: reserve1, reserveDen: reserve0 });
    ctx.prices = LQ.Prices({ oracleNum: oracleNumerator, oracleDen: 1e18, poolPriceAbove: true, diffBps: 0 });
    ctx.incentiveBps = 50;
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e18;
    ctx.token0 = debtToken;
    ctx.token1 = collToken;
    ctx.isToken0Debt = true;

    // Set stability pool balance high enough to cover full expansion
    setStabilityPoolBalance(debtToken, 1e18 + (reserve1 * 1e18) / oracleNumerator);
    setStabilityPoolMinBalance(1e18);

    (uint256 priceDiffBefore, bool priceAboveBefore) = calculatePriceDifference(ctx);
    assertTrue(priceAboveBefore, "Pool price should be above oracle");
    assertGe(priceDiffBefore, 999, "Price diff should be at least 10%");

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand");
    assertEq(action.amount0Out, 0, "No debt should flow out");
    assertGt(action.amount1Out, 0, "Collateral should flow out");
    assertGt(action.inputAmount, 0, "Debt should flow in");

    (uint256 priceDiffAfter, ) = calculatePriceDifference(ctx, action);
    assertEq(priceDiffAfter, 0, "Price should reach oracle");
    assertIncentive(50, false, action.amount1Out, action.inputAmount, oracleNumerator, 1e18);
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_whenToken1DebtPoolPriceBelowAndEnoughLiquidity_shouldExpandToOraclePrice(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken1Debt(6, 18) addFpmm(0, 50, 9000) boundFuzzParams(oracleNumerator, reserve0, reserve1, false) {
    LQ.Context memory ctx;
    ctx.pool = address(fpmm);
    ctx.reserves = LQ.Reserves({ reserveNum: reserve1, reserveDen: reserve0 });
    ctx.prices = LQ.Prices({ oracleNum: oracleNumerator, oracleDen: 1e18, poolPriceAbove: false, diffBps: 0 });
    ctx.incentiveBps = 50;
    ctx.token0Dec = 1e6;
    ctx.token1Dec = 1e18;
    ctx.token0 = collToken;
    ctx.token1 = debtToken;
    ctx.isToken0Debt = false;

    // Set stability pool balance high enough
    uint256 r0Norm = reserve0 * 1e12;
    {
      uint256 temp = (r0Norm * oracleNumerator) / 1e18;
      setStabilityPoolBalance(debtToken, 1e18 + temp);
      setStabilityPoolMinBalance(1e18);
    }

    (uint256 priceDiffBefore, bool priceAboveBefore) = calculatePriceDifference(oracleNumerator, 1e18, reserve1, r0Norm);
    assertFalse(priceAboveBefore, "Pool price should be below oracle");
    assertGe(priceDiffBefore, 999, "Price diff should be at least 10%");

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand");
    assertGt(action.amount0Out, 0, "Collateral should flow out");
    assertEq(action.amount1Out, 0, "No debt should flow out");
    assertGt(action.inputAmount, 0, "Debt should flow in");

    uint256 r1After = reserve1 + action.inputAmount;
    uint256 r0After = r0Norm - action.amount0Out * 1e12;
    (uint256 priceDiffAfter, ) = calculatePriceDifference(oracleNumerator, 1e18, r1After, r0After);
    assertEq(priceDiffAfter, 0, "Price should reach oracle");
    assertIncentive(50, true, action.amount0Out * 1e12, action.inputAmount, oracleNumerator, 1e18);
  }

  /* ============================================================ */
  /* ============== Contraction Fuzz Tests ====================== */
  /* ============================================================ */

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_whenToken0DebtPoolPriceBelowAndRedemptionFeeAllows_shouldContract(
    uint256 oracleNumerator,
    uint256 reserve0,
    uint256 reserve1
  ) public fpmmToken0Debt(18, 6) addFpmm(0, 50, 9000) boundFuzzParams(oracleNumerator, reserve0, reserve1, false) {
    LQ.Context memory ctx;
    ctx.pool = address(fpmm);
    ctx.reserves = LQ.Reserves({ reserveNum: reserve1, reserveDen: reserve0 });
    ctx.prices = LQ.Prices({ oracleNum: oracleNumerator, oracleDen: 1e18, poolPriceAbove: false, diffBps: 0 });
    ctx.incentiveBps = 50;
    ctx.token0Dec = 1e18;
    ctx.token1Dec = 1e6;
    ctx.token0 = debtToken;
    ctx.token1 = collToken;
    ctx.isToken0Debt = true;

    (uint256 priceDiffBefore, bool priceAboveBefore) = calculatePriceDifference(oracleNumerator, 1e18, reserve1 * 1e12, reserve0);

    assertFalse(priceAboveBefore, "Pool price should be below oracle");
    assertGe(priceDiffBefore, 999, "Price diff should be at least 10%");

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    // Ensure redemption fraction is below 0.25% resulting in total redemption fee less than 0.5%
    {
      uint256 r1Normalized = reserve1 * 1e12;
      uint256 totalSupply = (r1Normalized * 1e18 * 10_000) / oracleNumerator;
      setDebtTokenTotalSupply(totalSupply);
    }
    mockCollateralRegistryOracleRate(oracleNumerator, 1e18);

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract), "Should contract");
    assertGt(action.amount0Out, 0, "Debt should flow out");
    assertEq(action.amount1Out, 0, "No collateral should flow out");
    assertGt(action.inputAmount, 0, "Collateral should flow in");

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      oracleNumerator,
      1e18,
      reserve1 * 1e12 + action.inputAmount * 1e12,
      reserve0 - action.amount0Out
    );

    // Price difference should be less than before
    assertLt(priceDiffAfter, priceDiffBefore, "Price should improve");
    assertIncentive(50, true, action.amount0Out, action.inputAmount * 1e12, oracleNumerator, 1e18);
  }
}
