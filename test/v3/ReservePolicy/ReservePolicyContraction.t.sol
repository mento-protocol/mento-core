// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReservePolicyBaseTest } from "./ReservePolicyBaseTest.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract ReservePolicyContractionTest is ReservePolicyBaseTest {
  /* ============================================================ */
  /* ================= Contraction Tests ======================== */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceBelowOracle_shouldReturnContractAction() public view {
    // Pool has excess token0: 200 token0 vs 100 token1 at 1:1 oracle price
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18,  // token0 reserves (debt)
      reserveNum: 100e18,  // token1 reserves (collateral)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 500 // 5%
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act when pool has excess debt");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract), "Should contract when pool price below oracle");
    assertEq(uint256(action.liquiditySource), uint256(LQ.LiquiditySource.Reserve), "Should use Reserve as source");
    assertEq(action.pool, POOL, "Should target correct pool");
    assertEq(action.amount1Out, 0, "No collateral should flow out during contraction");
    assertGt(action.amount0Out, 0, "Debt should flow out during contraction");
    assertGt(action.inputAmount, 0, "Should have collateral input amount");
    assertEq(action.incentiveBps, 500, "Should use provided incentive");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithDifferentDecimals_shouldHandleCorrectly() public view {
    // Test with 6 decimal token1 and 18 decimal token0
    // Reserves are normalized to 18 decimals: 100 token1 = 100e18 normalized
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 200e18,  // token0 reserves
      reserveNum: 100e18,  // token1 reserves normalized to 18 decimals
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 500,
      token0Dec: 1e18,
      token1Dec: 1e6
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with different decimals");
    assertGt(action.amount0Out, 0, "Should have debt output in raw units");
    assertGt(action.inputAmount, 0, "Should have collateral input in raw units");
    // Verify the input is in 6-decimal scale
    assertLt(action.inputAmount, 1e12, "Collateral input should be in 6-decimal scale");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithZeroIncentive_shouldReturnCorrectAmounts() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18,  // token0 reserves
      reserveNum: 100e18,  // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 0
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act even with zero incentive");
    assertEq(action.incentiveBps, 0, "Should have zero incentive");
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
      reserveDen: 200e18,  // token0 reserves
      reserveNum: 100e18,  // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 10000 // 100%
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with maximum incentive");
    assertEq(action.incentiveBps, 10000, "Should have maximum incentive");
    // Formula: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Y = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * 1)
    // Y = 100e18 / 1 = 100e18 (token0 to remove)
    assertEq(action.amount0Out, 100e18, "Should calculate correct debt out");
    // X = Y * (ON/OD) * (1 - i) = 100e18 * (1e18/1e18) * 0 = 0 (token1 to add)
    // In contraction: collateral flows in via inputAmount
    assertEq(action.inputAmount, 0, "Should calculate correct collateral input amount with 100% incentive");
  }

  /* ============================================================ */
  /* ================= Contraction Formula Tests =============== */
  /* ============================================================ */

  function test_formulaValidation_whenPPLessThanOP_shouldFollowExactFormula() public view {
    // PP < OP: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Test with specific values that give clean division: RN=100, RD=500, ON=2, OD=1, i=0
    LQ.Context memory ctx = _createContext({
      reserveDen: 500e18,   // RD (token0)
      reserveNum: 100e18,   // RN (token1)
      oracleNum: 2e18,      // ON
      oracleDen: 1e18,      // OD
      poolPriceAbove: false,
      incentiveBps: 0       // 0% for clean calculation
    });

    (, LQ.Action memory action) = reservePolicy.determineAction(ctx);

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
    // Test X = Y * (ON/OD) * (1 - i) relationship for contraction (PP < OP)
    uint256[3] memory incentives = [uint256(0), 1500, 5000];
    
    for (uint i = 0; i < incentives.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 450e18,  // token0 reserves
        reserveNum: 150e18,  // token1 reserves
        oracleNum: 3e18,
        oracleDen: 2e18,
        poolPriceAbove: false,
        incentiveBps: incentives[i]
      });

      (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);
      
      if (shouldAct && action.inputAmount > 0) {
        // X/Y should equal (ON/OD) * (1 - i) (X is inputAmount, Y is amount0Out) within precision limits
        uint256 calculatedRatio = (action.inputAmount * ctx.prices.oracleDen * LQ.BASIS_POINTS_DENOMINATOR) / (action.amount0Out * ctx.prices.oracleNum);
        uint256 expectedRatio = LQ.BASIS_POINTS_DENOMINATOR - incentives[i];
        // Allow for rounding errors (1 wei difference)
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "X/Y ratio should approximately equal (ON/OD) * (1 - i)");
      }
    }
  }
}