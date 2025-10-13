// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract ReserveLiquidityStrategy_ActionExpansionTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Expansion Tests ========================== */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceAboveOracle_shouldReturnExpandAction() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100 // 1% (capped at FPMM max)
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand when pool price above oracle");
    assertEq(action.amount0Out, 0, "No debt should flow out during expansion");
    assertGt(action.amount1Out, 0, "Collateral should flow out during expansion");
    assertGt(action.amountOwedToPool, 0, "Should have debt input amount");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithDifferentDecimals_shouldHandleCorrectly() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test with 6 decimal token1 and 18 decimal token0
    // Reserves are normalized to 18 decimals: 200 token1 = 200e18 normalized
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 100e18, // 100 token0 (18 decimals)
      reserveNum: 200e18, // 200 token1 normalized to 18 decimals
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100,
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have collateral output in raw units");
    assertGt(action.amountOwedToPool, 0, "Should have debt input in raw units");
    // Verify the output is in 6-decimal scale
    assertLt(action.amount1Out, 1e12, "Collateral output should be in 6-decimal scale");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithZeroIncentive_shouldReturnCorrectAmounts() public fpmmToken0Debt(18, 18) addFpmm(0, 0) {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 0
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 0) / 10000)
    // X = 100e18 / 2 = 50e18
    assertEq(action.amount1Out, 50e18, "Should calculate correct collateral out with zero incentive");
    // Y = X * OD/ON = 50e18 * 1e18/1e18 = 50e18 (debt flows into pool)
    // In expansion: debt flows in via inputAmount
    assertEq(action.amountOwedToPool, 50e18, "Should calculate correct debt input amount");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithMaxIncentive_shouldReturnCorrectAmounts() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 10000 // 100%
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 10000) / 10000)
    // X = 100e18 / 1 = 100e18
    assertEq(action.amount1Out, 100e18, "Should calculate correct collateral out with max incentive");
    // Y = X * OD/ON * (1 - i) = 100e18 * 1e18/1e18 * (1 - 1) = 0
    // With 100% incentive, all goes to incentive, nothing flows to pool
    assertEq(action.amountOwedToPool, 0, "Should be zero with 100% incentive");
  }

  /* ============================================================ */
  /* ================= Expansion Formula Tests ================== */
  /* ============================================================ */

  function test_formulaValidation_whenPPGreaterThanOP_shouldFollowExactFormula() public fpmmToken0Debt(18, 18) addFpmm(0, 0) {
    // PP > OP: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // Test with specific values that give clean division: RN=400, RD=100, ON=2, OD=1, i=0
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // RD (token0)
      reserveNum: 400e18, // RN (token1)
      oracleNum: 2e18, // ON
      oracleDen: 1e18, // OD
      poolPriceAbove: true,
      incentiveBps: 0 // 0% for clean calculation
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    // Manual calculation:
    // X = (1e18 * 400e18 - 2e18 * 100e18) / (1e18 * 2)
    // X = (400e18 - 200e18) / 2 = 200e18 / 2 = 100e18
    uint256 expectedX = 100e18;
    assertEq(action.amount1Out, expectedX, "X calculation should match formula");

    // Y = X * OD/ON = 100e18 * 1e18/2e18 = 50e18
    uint256 expectedY = 50e18;
    assertEq(action.amountOwedToPool, expectedY, "Y should equal X * OD/ON");
  }

  function test_YRelationship_shouldAlwaysHoldForExpansion() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test Y = X * OD/ON * (1 - i) relationship for expansion (PP > OP)
    uint256[3] memory incentives = [uint256(0), 100, 100]; // Capped at 1%

    for (uint256 i = 0; i < incentives.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 150e18, // token0 reserves
        reserveNum: 450e18, // token1 reserves
        oracleNum: 3e18,
        oracleDen: 2e18,
        poolPriceAbove: true,
        incentiveBps: incentives[i]
      });

      (, LQ.Action memory action) = strategy.determineAction(ctx);

      if (action.amount1Out > 0) {
        // Y/X should equal OD/ON * (1 - i) (Y is amountOwedToPool, X is amount1Out) within precision limits
        uint256 calculatedRatio = (action.amountOwedToPool * ctx.prices.oracleNum) / action.amount1Out;
        // Apply incentive multiplier to expected ratio
        uint256 expectedRatio = (ctx.prices.oracleDen * (10000 - ctx.incentiveBps)) / 10000;
        // Allow for rounding errors (1 wei difference)
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "Y/X ratio should approximately equal OD/ON * (1 - i)");
      }
    }
  }
}
