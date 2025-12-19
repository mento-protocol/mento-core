// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy_ActionContractionTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ============== Contraction target liquidity ================ */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceBelowRebalanceThreshold_shouldContractAndBringPriceBackToRebalanceThreshold()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    uint256 reserve0 = 7_089_031 * 1e18; // brl.m 1.3Mio in $
    uint256 reserve1 = 1_000_000 * 1e6; // usd.m 1Mio in $

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 1e18, // USD/BRL rate
      oracleDen: 5476912800000000000,
      poolPriceAbove: false,
      isToken0Debt: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 25,
        protocolIncentiveBpsExpansion: 25,
        liquiditySourceIncentiveBpsContraction: 25,
        protocolIncentiveBpsContraction: 25
      })
    });

    (uint256 priceDiffBefore, bool poolPriceAboveBefore) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum,
      ctx.reserves.reserveDen
    );
    assertFalse(poolPriceAboveBefore, "Pool price should be below oracle");
    assertGt(priceDiffBefore, 500, "Price difference should be greater than rebalance threshold");

    LQ.Action memory action = strategy.determineAction(ctx);

    // amount out in token 0 := (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // = 646615.244215938303341902
    uint256 expectedAmount0Out = 646615244215938303341902;
    uint256 expectedAmount1Out = 0;

    // input amount in token 1 := (amountOut * ON * (1-i))/OD = 117471683681
    uint256 expectedAmountOwedToPool = 117471683681;

    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum + expectedAmountOwedToPool * (1e18 / ctx.token1Dec),
      ctx.reserves.reserveDen - expectedAmount0Out
    );
    assertFalse(poolPriceAboveAfter, "Pool price should be below oracle");
    assertEq(priceDiffAfter, 500, "Price difference should be equal to rebalance threshold");

    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
    assertIncentive(
      ctx.incentives.liquiditySourceIncentiveBpsContraction + ctx.incentives.protocolIncentiveBpsContraction,
      true,
      expectedAmount0Out,
      expectedAmountOwedToPool * (1e18 / ctx.token1Dec),
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }

  function test_determineAction_whenToken1DebtPoolPriceAboveRebalanceThreshold_shouldContractAndBringPriceBackToRebalanceThreshold()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 9000, 100, 25, 25, 25, 25)
  {
    uint256 reserve0 = 10_000_000 * 1e18; // usd.m
    uint256 reserve1 = 14_500_000 * 1e6; // chf.m

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 1e18,
      oracleDen: 1242930830000000000,
      poolPriceAbove: true,
      isToken0Debt: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 25,
        protocolIncentiveBpsExpansion: 25,
        liquiditySourceIncentiveBpsContraction: 25,
        protocolIncentiveBpsContraction: 25
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

    LQ.Action memory action = strategy.determineAction(ctx);

    uint256 expectedAmount0Out = 0;
    // amount out in token 1 := (RN * TD - TN * RD) / (TD + TN * (1 - i) * OD/ON)  =
    uint256 expectedAmount1Out = 2959885068535;
    // input amount in token 0 := (amountOut * OD * (1-i))/ON = 2942403628118
    uint256 expectedAmountOwedToPool = 3660537742914120361879750;

    (uint256 priceDiffAfter, bool poolPriceAboveAfter) = calculatePriceDifference(
      ctx.prices.oracleNum,
      ctx.prices.oracleDen,
      ctx.reserves.reserveNum - action.amount1Out * (1e18 / ctx.token1Dec),
      ctx.reserves.reserveDen + action.amountOwedToPool
    );
    assertTrue(poolPriceAboveAfter, "Pool price should be above oracle");
    assertEq(priceDiffAfter, 500, "Price difference should be equal to rebalance threshold");

    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, expectedAmountOwedToPool);
    assertIncentive(
      ctx.incentives.liquiditySourceIncentiveBpsContraction + ctx.incentives.protocolIncentiveBpsContraction,
      false,
      expectedAmount1Out * (1e18 / ctx.token1Dec),
      expectedAmountOwedToPool,
      ctx.prices.oracleNum,
      ctx.prices.oracleDen
    );
  }
}
