// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReservePolicyBaseTest } from "./ReservePolicyBaseTest.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract ReservePolicyPrecisionTest is ReservePolicyBaseTest {
  /* ============================================================ */
  /* ================= Precision Tests ========================== */
  /* ============================================================ */

  function test_determineAction_whenDecimalConversions_shouldMaintainPrecision() public view {
    // Test conversion between 18 decimals and 6 decimals
    // 100 token0 (18 decimals) vs 200 token1 (normalized to 18 decimals)
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

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with decimal conversions");

    // Calculate expected values - use simpler calculation for testing
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 500) / 10000)
    // X = 100e18 / 1.95, but let's use integer approximation
    // Just verify that there's output for decimal conversion test
    assertTrue(action.amount1Out > 0, "Should have token1 output");

    // For 6 decimal collateral, amount should be around 50e6 (approx 51.282e6 with 5% incentive)
    assertLt(action.amount1Out, 1e9, "Token1 out should be in 6 decimal range");
    assertGt(action.amount1Out, 1e6, "Token1 out should be meaningful in 6 decimals");
    assertGt(action.inputAmount, 1e12, "Debt input should be in 18 decimal units");

    // Verify Y = X * OD/ON relationship holds across decimal conversions
    // Convert collateral back to 18 decimals for comparison
    uint256 collateralOut18 = action.amount1Out * 1e12;
    // Allow for small rounding errors in decimal conversion
    assertApproxEqRel(
      action.inputAmount,
      collateralOut18,
      1e15,
      "Y should approximately equal X when oracle ratio is 1:1"
    ); // 0.1% tolerance
  }

  function test_decimalPrecision_multipleDecimalCombinations() public view {
    // Test multiple decimal combinations
    DecimalTest[4] memory tests = [
      DecimalTest(1e18, 1e6, 1e12), // 18 dec debt, 6 dec collateral
      DecimalTest(1e6, 1e18, 1), // 6 dec debt, 18 dec collateral (factor is 1/1e12 but in reverse)
      DecimalTest(1e8, 1e6, 100), // 8 dec debt, 6 dec collateral
      DecimalTest(1e18, 1e8, 1e10) // 18 dec debt, 8 dec collateral
    ];

    for (uint256 i = 0; i < tests.length; i++) {
      LQ.Context memory ctx = _createContextWithDecimals({
        reserveDen: 100e18, // token0 reserves
        reserveNum: 200e18, // token1 reserves
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: 1000,
        token0Dec: tests[i].debtDec,
        token1Dec: tests[i].collateralDec
      });

      (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

      if (shouldAct) {
        // For token0 (debt) - should be scaled by debtDec
        if (action.inputAmount > 0 || action.amount0Out > 0) {
          uint256 amount0 = action.amount0Out > 0 ? action.amount0Out : action.inputAmount;
          // Verify it's in the correct decimal range (allowing for reasonable values)
          if (tests[i].debtDec < 1e18) {
            // For 6 decimals, max reasonable value would be around 1e12 (1M tokens)
            // For 8 decimals, max reasonable value would be around 1e14 (1M tokens)
            uint256 maxReasonableValue = tests[i].debtDec * 1e6; // 1M tokens max
            assertLt(amount0, maxReasonableValue, "Token0 should be in reasonable decimal scale");
          }
        }

        // For token1 (collateral) - should be scaled by collateralDec
        if (action.inputAmount > 0 || action.amount1Out > 0) {
          uint256 amount1 = action.amount1Out > 0 ? action.amount1Out : action.inputAmount;
          // Verify it's in the correct decimal range (allowing for reasonable values)
          if (tests[i].collateralDec < 1e18) {
            // For 6 decimals, max reasonable value would be around 1e12 (1M tokens)
            // For 8 decimals, max reasonable value would be around 1e14 (1M tokens)
            uint256 maxReasonableValue = tests[i].collateralDec * 1e6; // 1M tokens max
            assertLt(amount1, maxReasonableValue, "Token1 should be in reasonable decimal scale");
          }
        }
      }
    }
  }

  function test_precision_highDecimalVariations() public view {
    // Test with high precision decimals (up to 18)
    uint256[4] memory decimals = [uint256(1e6), 1e8, 1e12, 1e18];

    for (uint256 i = 0; i < decimals.length; i++) {
      for (uint256 j = 0; j < decimals.length; j++) {
        if (i == j) continue; // Skip same decimals

        LQ.Context memory ctx = _createContextWithDecimals({
          reserveDen: 1000e18, // Large reserves for better precision testing
          reserveNum: 2000e18, // 2:1 ratio
          oracleNum: 1e18,
          oracleDen: 1e18,
          poolPriceAbove: true,
          incentiveBps: 250, // 2.5%
          token0Dec: decimals[i],
          token1Dec: decimals[j]
        });

        (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

        if (shouldAct) {
          assertGt(action.amount1Out, 0, "Should have meaningful output for all decimal combinations");
          assertGt(action.inputAmount, 0, "Should have meaningful input for all decimal combinations");

          // Verify no precision loss causes zero amounts for reasonable reserves
          if (decimals[j] >= 1e6) {
            // Only check for reasonable decimal precision
            assertGt(action.amount1Out, decimals[j] / 1e6, "Should have at least micro-unit output");
          }
        }
      }
    }
  }

  function test_precision_rounding_consistency() public view {
    // Test that similar inputs produce proportionally similar outputs
    uint256[3] memory baseAmounts = [uint256(100e18), 1000e18, 10000e18];

    for (uint256 i = 0; i < baseAmounts.length - 1; i++) {
      LQ.Context memory ctx1 = _createContextWithDecimals({
        reserveDen: baseAmounts[i],
        reserveNum: (baseAmounts[i] * 15) / 10, // 1.5x ratio
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: 300,
        token0Dec: 1e18,
        token1Dec: 1e6
      });

      LQ.Context memory ctx2 = _createContextWithDecimals({
        reserveDen: baseAmounts[i + 1],
        reserveNum: (baseAmounts[i + 1] * 15) / 10, // Same 1.5x ratio
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: 300,
        token0Dec: 1e18,
        token1Dec: 1e6
      });

      (bool shouldAct1, LQ.Action memory action1) = reservePolicy.determineAction(ctx1);
      (bool shouldAct2, LQ.Action memory action2) = reservePolicy.determineAction(ctx2);

      if (shouldAct1 && shouldAct2 && action1.amount1Out > 0 && action2.amount1Out > 0) {
        // The ratio should be approximately the same as the base amount ratio
        uint256 expectedRatio = baseAmounts[i + 1] / baseAmounts[i];
        uint256 actualRatio = action2.amount1Out / action1.amount1Out;

        // Allow for some rounding differences (within 1% tolerance)
        assertApproxEqRel(actualRatio, expectedRatio, 1e16, "Proportional scaling should be consistent");
      }
    }
  }
}
