// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReservePolicyBaseTest, ReserveLiquidityStrategyHarness } from "./ReservePolicyBaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract ReservePolicyExpansionTest is ReservePolicyBaseTest {
  ReserveLiquidityStrategyHarness public reserveLS;
  address public mockReserve = makeAddr("mockReserve");

  function setUp() public override {
    super.setUp();
    reserveLS = new ReserveLiquidityStrategyHarness(mockReserve);
  }

  /* ============================================================ */
  /* ================= Expansion Tests ========================== */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceAboveOracle_shouldReturnExpandAction() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 500 // 5%
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act when pool has excess collateral");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand when pool price above oracle");
    assertEq(action.pool, POOL, "Should target correct pool");
    assertTrue(action.amount0Out == 0 || action.amount1Out > 0, "Should have correct token flows for expansion");
    assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have token outflow during expansion");
    assertGt(action.inputAmount, 0, "Should have debt input amount");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithDifferentDecimals_shouldHandleCorrectly() public view {
    // Test with 6 decimal token1 and 18 decimal token0
    // Reserves are normalized to 18 decimals: 200 token1 = 200e18 normalized
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 100e18, // 100 token0 (18 decimals)
      reserveNum: 200e18, // 200 token1 normalized to 18 decimals
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 500,
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with different decimals");
    assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have token output in raw units");
    assertGt(action.inputAmount, 0, "Should have debt input in raw units");
    assertTrue(
      action.amount0Out < 1e12 || action.amount1Out < 1e12,
      "Token out should be in appropriate decimal scale"
    );
  }

  function test_determineAction_whenPoolPriceAboveOracleWithZeroIncentive_shouldReturnCorrectAmounts() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 0
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act even with zero incentive");
    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 0) / 10000)
    // X = 100e18 / 2 = 50e18
    assertEq(action.amount1Out, 50e18, "Should calculate correct collateral out with zero incentive");
    // Y = X * OD/ON = 50e18 * 1e18/1e18 = 50e18 (debt flows into pool)
    // In expansion: debt flows in via inputAmount
    assertEq(action.inputAmount, 50e18, "Should calculate correct debt input amount");
  }

  function test_determineAction_whenPoolPriceAboveOracleWithMaxIncentive_shouldReturnCorrectAmounts() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 10000 // 100%
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with maximum incentive");
    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 10000) / 10000)
    // X = 100e18 / 1 = 100e18
    assertEq(action.amount1Out, 100e18, "Should calculate correct collateral out with max incentive");
    // Y = X * OD/ON = 100e18 * 1e18/1e18 = 100e18 (debt flows into pool)
    // In expansion: debt flows in via inputAmount
    assertEq(action.inputAmount, 100e18, "Should calculate correct debt input amount");
  }

  /* ============================================================ */
  /* ================= Expansion Formula Tests ================== */
  /* ============================================================ */

  function test_formulaValidation_whenPPGreaterThanOP_shouldFollowExactFormula() public view {
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

    (, LQ.Action memory action) = reserveLS.determineAction(ctx);

    // Manual calculation:
    // X = (1e18 * 400e18 - 2e18 * 100e18) / (1e18 * 2)
    // X = (400e18 - 200e18) / 2 = 200e18 / 2 = 100e18
    uint256 expectedX = 100e18;
    assertEq(action.amount1Out, expectedX, "X calculation should match formula");

    // Y = X * OD/ON = 100e18 * 1e18/2e18 = 50e18
    uint256 expectedY = 50e18;
    assertEq(action.inputAmount, expectedY, "Y should equal X * OD/ON");
  }

  function test_YRelationship_shouldAlwaysHoldForExpansion() public view {
    // Test Y = X * OD/ON relationship for expansion (PP > OP)
    uint256[3] memory incentives = [uint256(0), 500, 2000];

    for (uint256 i = 0; i < incentives.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 150e18, // token0 reserves
        reserveNum: 450e18, // token1 reserves
        oracleNum: 3e18,
        oracleDen: 2e18,
        poolPriceAbove: true,
        incentiveBps: incentives[i]
      });

      (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

      if (shouldAct && action.amount1Out > 0) {
        // Y/X should equal OD/ON (Y is inputAmount, X is amount1Out) within precision limits
        uint256 calculatedRatio = (action.inputAmount * ctx.prices.oracleNum) / action.amount1Out;
        uint256 expectedRatio = ctx.prices.oracleDen;
        // Allow for rounding errors (1 wei difference)
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "Y/X ratio should approximately equal OD/ON");
      }
    }
  }
}
