// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReservePolicyBaseTest, ReserveLiquidityStrategyHarness } from "./ReservePolicyBaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract ReservePolicyContractionTest is ReservePolicyBaseTest {
  ReserveLiquidityStrategyHarness public reserveLS;
  address public mockReserve = makeAddr("mockReserve");

  function setUp() public override {
    super.setUp();
    reserveLS = new ReserveLiquidityStrategyHarness(mockReserve);
  }

  /* ============================================================ */
  /* ================= Contraction Tests ======================== */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceBelowOracle_shouldReturnContractAction() public view {
    // Pool has excess token0: 200 token0 vs 100 token1 at 1:1 oracle price
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves (debt)
      reserveNum: 100e18, // token1 reserves (collateral)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 500 // 5%
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act when pool has excess debt");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract), "Should contract when pool price below oracle");
    assertEq(action.pool, POOL, "Should target correct pool");
    assertEq(action.amount1Out, 0, "No collateral should flow out during contraction");
    assertGt(action.amount0Out, 0, "Debt should flow out during contraction");
    assertGt(action.inputAmount, 0, "Should have collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithDifferentDecimals_shouldHandleCorrectly() public view {
    // Test with 6 decimal token1 and 18 decimal token0
    // Reserves are normalized to 18 decimals: 100 token1 = 100e18 normalized
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves normalized to 18 decimals
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 500,
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with different decimals");
    assertGt(action.amount0Out, 0, "Should have debt output in raw units");
    assertGt(action.inputAmount, 0, "Should have collateral input in raw units");
    // Verify the input is in 6-decimal scale
    assertLt(action.inputAmount, 1e12, "Collateral input should be in 6-decimal scale");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithZeroIncentive_shouldReturnCorrectAmounts() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 0
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act even with zero incentive");
    // NOTE: incentiveBps is in context, not in action in the new architecture
    // Formula: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Y = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * 2)
    // Y = 100e18 / 2 = 50e18 (token0 to remove)
    assertEq(action.amount0Out, 50e18, "Should calculate correct debt out");
    // X = Y * (ON/OD) * (1 - i) = 50e18 * (1e18/1e18) * 1 = 50e18 (token1 to add)
    // In contraction: collateral flows in via inputAmount
    assertEq(action.inputAmount, 50e18, "Should calculate correct collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithMaxIncentive_shouldReturnCorrectAmounts() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 10000 // 100%
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with maximum incentive");
    // NOTE: In new architecture, the incentive is applied in the denominator formula:
    // denominator = (OD * (2 * 10000 - incentiveBps)) / 10000
    // With 100% incentive: denominator = (1e18 * (20000 - 10000)) / 10000 = 1e18
    // numerator = ON * RD - OD * RN = 1e18 * 200e18 - 1e18 * 100e18 = 100e18
    // token1In = numerator / denominator = 100e18 / 1e18 = 100e18
    // token0Out = token1In * (OD / ON) = 100e18 * (1e18 / 1e18) = 100e18
    assertEq(action.amount0Out, 100e18, "Should calculate correct debt out");
    assertEq(action.inputAmount, 100e18, "Should calculate correct collateral input amount with 100% incentive");
  }

  /* ============================================================ */
  /* ================= Contraction Formula Tests =============== */
  /* ============================================================ */

  function test_formulaValidation_whenPPLessThanOP_shouldFollowExactFormula() public view {
    // PP < OP: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Test with specific values that give clean division: RN=100, RD=500, ON=2, OD=1, i=0
    LQ.Context memory ctx = _createContext({
      reserveDen: 500e18, // RD (token0)
      reserveNum: 100e18, // RN (token1)
      oracleNum: 2e18, // ON
      oracleDen: 1e18, // OD
      poolPriceAbove: false,
      incentiveBps: 0 // 0% for clean calculation
    });

    (, LQ.Action memory action) = reserveLS.determineAction(ctx);

    // Manual calculation:
    // Y = (2e18 * 500e18 - 1e18 * 100e18) / (2e18 * 2)
    // Y = (1000e18 - 100e18) / 4e18 = 900e18 / 4e18 = 225e18
    uint256 expectedY = 225e18;
    assertEq(action.amount0Out, expectedY, "Y calculation should match formula (token0 out)");
    // For PP < OP, token1 flows in via inputAmount and token0 flows out

    // X = Y * (ON/OD) * (1 - i) = 225e18 * (2e18/1e18) * 1 = 450e18
    uint256 expectedX = 450e18;
    assertEq(action.inputAmount, expectedX, "X should equal Y * (ON/OD) * (1 - i)");
  }

  function test_YRelationship_shouldAlwaysHoldForContraction() public view {
    // NOTE: In new architecture, the formula is different from the old one
    // The old formula had: X = Y * (ON/OD) * (1 - i)
    // The new formula in _handlePoolPriceBelow calculates:
    // token1In = numerator / denominator where denominator = (OD * (2 * 10000 - incentiveBps)) / 10000
    // token0Out = token1In * (OD / ON)
    // So the relationship is: token1In / token0Out = ON / OD (independent of incentive)
    uint256[3] memory incentives = [uint256(0), 1500, 5000];

    for (uint256 i = 0; i < incentives.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 450e18, // token0 reserves
        reserveNum: 150e18, // token1 reserves
        oracleNum: 3e18,
        oracleDen: 2e18,
        poolPriceAbove: false,
        incentiveBps: incentives[i]
      });

      (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

      if (shouldAct && action.inputAmount > 0) {
        // In new architecture: token0Out = token1In * (OD / ON)
        // So: token1In / token0Out = ON / OD
        uint256 calculatedRatio = (action.inputAmount * ctx.prices.oracleDen) / (action.amount0Out * ctx.prices.oracleNum);
        uint256 expectedRatio = 1;
        // Allow for rounding errors
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "token1In / token0Out should equal ON / OD");
      }
    }
  }
}
