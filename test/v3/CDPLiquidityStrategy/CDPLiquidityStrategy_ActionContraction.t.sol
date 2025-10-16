// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy_ActionContractionTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ============= Contraction Token 0 Debt Tests ============== */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceBelowAndRedemptionFeeAllows_shouldContractToOraclePrice()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    // Setup: Pool price below oracle (excess debt scenario for token0 debt)
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 1_500_000e18, // token0 (debt) reserves
      reserveNum: 1_000_000e6, // token1 (collateral) reserves (6 decimals)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50, // 0.5%
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    // Mock redemption rate at 0.25% (leaves 0.25% room for redemption within 0.5% incentive)
    mockRedemptionRateWithDecay(0.0025 * 1e18);

    // Set total supply high enough that redemption fee stays below incentive
    uint256 totalSupply = (ctx.reserves.reserveNum * 1e12 * ctx.prices.oracleDen * 10_000) / ctx.prices.oracleNum;
    setDebtTokenTotalSupply(totalSupply);

    // Mock collateral registry oracle rate
    mockCollateralRegistryOracleRate(ctx.prices.oracleNum, ctx.prices.oracleDen);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum * 1e12, // normalize to 18 decimals
      ctx.reserves.reserveDen
    );

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract");
    assertGt(action.amount0Out, 0, "Debt should flow out during contraction");
    assertEq(action.amount1Out, 0, "No collateral should flow out during contraction");
    assertGt(action.amountOwedToPool, 0, "Collateral should flow in via amountOwedToPool");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum * 1e12 + action.amountOwedToPool * 1e12;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    // Price should improve (may not reach zero due to redemption fee)
    assertLt(priceDiffAfter, priceDiffBefore, "Price difference should decrease");
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      action.amountOwedToPool * 1e12,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  function test_determineAction_whenToken0DebtAndRedemptionFeeLimitsContraction_shouldContractPartially()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    // Setup: Pool price below oracle but redemption fee limits contraction amount
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 1_500_000e18, // token0 (debt) reserves
      reserveNum: 1_000_000e6, // token1 (collateral) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50,
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    // Mock redemption rate at 0.25%
    mockRedemptionRateWithDecay(0.0025 * 1e18);

    // Set lower total supply so redemption fraction increases redemption fee faster
    uint256 totalSupply = 100_000_000e18;
    setDebtTokenTotalSupply(totalSupply);

    mockCollateralRegistryOracleRate(ctx.prices.oracleNum, ctx.prices.oracleDen);

    (uint256 priceDiffBefore, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum * 1e12,
      ctx.reserves.reserveDen
    );

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum * 1e12 + action.amountOwedToPool * 1e12;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    // Price should improve but not reach zero due to redemption fee constraints
    assertLt(priceDiffAfter, priceDiffBefore, "Price difference should decrease");
    assertGt(priceDiffAfter, 0, "Price difference should still be positive (partial contraction)");

    // Verify the contraction was limited by redemption fee
    // Maximum redeemable should be limited by (incentive - decayedBaseFee) * totalSupply * beta
    uint256 maxRedeemable = (totalSupply * 1 * (50 * 1e14 - 0.0025 * 1e18)) / 1e18;
    assertLe(action.amount0Out, maxRedeemable, "Contraction should be limited by redemption fee");
  }

  /* ============================================================ */
  /* ============= Contraction Token 1 Debt Tests ============== */
  /* ============================================================ */

  function test_determineAction_whenToken1DebtPoolPriceAboveAndRedemptionFeeAllows_shouldContractToOraclePrice()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Pool price above oracle (excess debt scenario for token1 debt)
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 1_000_000e6, // token0 (collateral) reserves (6 decimals)
      reserveNum: 1_500_000e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 50,
      token0Dec: 1e6,
      token1Dec: 1e18
    });

    ctx.isToken0Debt = false;
    ctx.token0 = collToken;
    ctx.token1 = debtToken;

    // Mock redemption rate at 0.25%
    mockRedemptionRateWithDecay(0.0025 * 1e18);

    // Set total supply high enough
    uint256 totalSupply = (ctx.reserves.reserveDen * 1e12 * ctx.prices.oracleNum * 10_000) / ctx.prices.oracleDen;
    setDebtTokenTotalSupply(totalSupply);

    // For token1 debt, oracle rate is inverted
    mockCollateralRegistryOracleRate(ctx.prices.oracleDen, ctx.prices.oracleNum);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen * 1e12
    );

    assertTrue(poolPriceAboveBefore, "Pool price should be above oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract");
    assertEq(action.amount0Out, 0, "No collateral should flow out during contraction");
    assertGt(action.amount1Out, 0, "Debt should flow out during contraction");
    assertGt(action.amountOwedToPool, 0, "Collateral should flow in via amountOwedToPool");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen * 1e12 + action.amountOwedToPool * 1e12;
    uint256 reserve1After = ctx.reserves.reserveNum - action.amount1Out;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    // Price should improve
    assertLe(priceDiffAfter, priceDiffBefore, "Price difference should decrease or stay same");
    assertIncentive(
      ctx.incentiveBps,
      false,
      action.amount1Out,
      action.amountOwedToPool * 1e12,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  /* ============================================================ */
  /* ================ Redemption Fee Edge Cases ================ */
  /* ============================================================ */

  function test_determineAction_whenRedemptionFeeExceedsIncentive_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Redemption fee is higher than incentive
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_500_000e18,
      reserveNum: 1_000_000e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50 // 0.5% incentive
    });

    // Mock redemption rate at 0.6% (higher than 0.5% incentive)
    mockRedemptionRateWithDecay(0.006 * 1e18);

    setDebtTokenTotalSupply(1_000_000_000e18);
    mockCollateralRegistryOracleRate(ctx.prices.oracleNum, ctx.prices.oracleDen);

    // Should revert because redemption fee exceeds incentive
    vm.expectRevert();
    strategy.determineAction(ctx);
  }

  function test_determineAction_whenRedemptionFeeEqualsIncentive_shouldContractToExactOraclePrice()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Calculate supply that makes redemption fee exactly equal to incentive
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_500_000e18,
      reserveNum: 1_000_000e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50
    });

    // Mock base redemption rate at 0.25%
    uint256 baseRate = 0.0025 * 1e18;
    mockRedemptionRateWithDecay(baseRate);

    // Calculate target amount to redeem (from ideal contraction formula)
    uint256 targetAmountToRedeem = (ctx.reserves.reserveNum *
      ctx.prices.oracleDen -
      ctx.reserves.reserveDen *
      ctx.prices.oracleNum) / ctx.prices.oracleDen;

    // Calculate supply where redemption fee equals incentive:
    // targetSupply = (targetAmount * 1e18) / (incentive - baseRate)
    uint256 targetSupply = (targetAmountToRedeem * 1e18) / (50 * 1e14 - baseRate);

    setDebtTokenTotalSupply(targetSupply);
    mockCollateralRegistryOracleRate(ctx.prices.oracleNum, ctx.prices.oracleDen);

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum + action.amountOwedToPool;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    // Price should reach exactly zero (or very close due to rounding)
    assertLe(priceDiffAfter, 1, "Price difference should be at or near zero");
  }

  /* ============================================================ */
  /* ================ Specific Scenario Tests ================== */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceBelowWith10PercentDifference_shouldContractCorrectly()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    // Specific scenario: 1.5M USDFX (debt) and 1M USDC (collateral)
    // Pool price is 10% below oracle price
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 1_500_000e18, // token0 (debt) reserves
      reserveNum: 1_000_000e6, // token1 (collateral) reserves (6 decimals)
      oracleNum: 999884980000000000, // ~1.0 USD/USDC
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50, // 0.5%
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    // Setup redemption parameters
    mockRedemptionRateWithDecay(3e15); // 0.3%
    setDebtTokenTotalSupply(10_000_000e18);
    mockCollateralRegistryOracleRate(ctx.prices.oracleNum, ctx.prices.oracleDen);

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum * 1e12, // normalize to 18 decimals
      ctx.reserves.reserveDen
    );

    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 0, "Price difference should be positive");

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract");
    assertGt(action.amount0Out, 0, "Debt should flow out");
    assertEq(action.amount1Out, 0, "No collateral should flow out");
    assertGt(action.amountOwedToPool, 0, "Collateral should flow in");

    // Calculate reserves after action
    uint256 reserve0After = ctx.reserves.reserveDen - action.amount0Out;
    uint256 reserve1After = ctx.reserves.reserveNum * 1e12 + action.amountOwedToPool * 1e12;

    (uint256 priceDiffAfter, ) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      reserve1After,
      reserve0After
    );

    // Price should improve
    assertLt(priceDiffAfter, priceDiffBefore, "Price difference should decrease");
    assertIncentive(
      ctx.incentiveBps,
      true,
      action.amount0Out,
      action.amountOwedToPool * 1e12,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }
}
