// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { ReservePolicyBaseTest } from "./ReservePolicyBaseTest.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";

contract ReservePolicyIntegrationTest is ReservePolicyBaseTest {
  /* ============================================================ */
  /* ================ Token Order Tests ======================== */
  /* ============================================================ */

  function test_determineAction_whenToken1IsDebt_shouldHandleCorrectly() public view {
    // Test when token1 is debt and token0 is collateral (isToken0Debt = false)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 100e18, // token0 (collateral) reserves
      reserveNum: 200e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 500,
      isToken0Debt: false // token1 is debt
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with reversed token order");
    // When token1 is debt and PP > OP, we still need to contract (remove excess debt)
    // Pool has 200 debt (token1) vs 100 collateral (token0) at 1:1 oracle, so pool price > oracle
    // This means too much debt relative to collateral, so we contract
    assertEq(
      uint256(action.dir),
      uint256(LQ.Direction.Contract),
      "Should contract when excess debt relative to collateral"
    );
    assertEq(action.amount0Out, 0, "No collateral (token0) should flow out");
    assertGt(action.amount1Out, 0, "Should have debt (token1) flowing out");
    assertGt(action.inputAmount, 0, "Should have collateral input amount");
  }

  function test_determineAction_whenToken0IsCollateral_shouldHandleExpansionCorrectly() public view {
    // Test expansion scenario when token0 is collateral (token1 is debt)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 200e18, // token0 (collateral) reserves
      reserveNum: 100e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true, // Pool has excess collateral relative to debt
      incentiveBps: 500,
      isToken0Debt: false // token1 is debt
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand when excess collateral");
    assertGt(action.amount0Out, 0, "Should have collateral (token0) flowing out");
    assertEq(action.amount1Out, 0, "No debt (token1) should flow out");
    assertGt(action.inputAmount, 0, "Should have debt input amount");
  }

  function test_determineAction_whenToken0IsCollateral_shouldHandleContractionCorrectly() public view {
    // Test contraction scenario when token0 is collateral (token1 is debt)
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 100e18, // token0 (collateral) reserves
      reserveNum: 200e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false, // Pool has excess debt relative to collateral
      incentiveBps: 500,
      isToken0Debt: false // token1 is debt
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract), "Should contract when excess debt");
    assertEq(action.amount0Out, 0, "No collateral (token0) should flow out");
    assertGt(action.amount1Out, 0, "Should have debt (token1) flowing out");
    assertGt(action.inputAmount, 0, "Should have collateral input amount");
  }

  /* ============================================================ */
  /* ================ Callback Data Tests ====================== */
  /* ============================================================ */

  function test_determineAction_callbackDataEncoding_shouldBeCorrect() public view {
    // Test that callback data is properly encoded
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18,
      reserveNum: 200e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 1000 // 10%
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act");

    // Decode callback data
    (uint256 incentiveAmount, bool isToken0Debt) = abi.decode(action.data, (uint256, bool));

    // Verify incentive amount is correct (10% of input amount)
    uint256 expectedIncentive = (action.inputAmount * 1000) / 10000;
    assertEq(incentiveAmount, expectedIncentive, "Incentive amount should be 10% of input");
    assertTrue(isToken0Debt, "Should indicate token0 is debt");
  }

  function test_determineAction_callbackDataEncoding_withReversedTokenOrder_shouldBeCorrect() public view {
    // Test callback data with reversed token order
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 100e18,
      reserveNum: 200e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 750, // 7.5%
      isToken0Debt: false // token1 is debt
    });

    (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act");

    // Decode callback data
    (uint256 incentiveAmount, bool isToken0Debt) = abi.decode(action.data, (uint256, bool));

    // Verify incentive amount is correct (7.5% of input amount)
    uint256 expectedIncentive = (action.inputAmount * 750) / 10000;
    assertEq(incentiveAmount, expectedIncentive, "Incentive amount should be 7.5% of input");
    assertFalse(isToken0Debt, "Should indicate token1 is debt");
  }

  function test_determineAction_callbackDataEncoding_withDifferentIncentives_shouldScaleCorrectly() public view {
    uint256[4] memory incentives = [uint256(100), 500, 1500, 5000]; // 1%, 5%, 15%, 50%

    for (uint256 i = 0; i < incentives.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 100e18,
        reserveNum: 150e18,
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: incentives[i]
      });

      (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

      if (shouldAct) {
        // Decode callback data
        (uint256 incentiveAmount, bool isToken0Debt) = abi.decode(action.data, (uint256, bool));

        // Verify incentive scaling
        uint256 expectedIncentive = (action.inputAmount * incentives[i]) / 10000;
        assertEq(incentiveAmount, expectedIncentive, "Incentive should scale proportionally");
        assertTrue(isToken0Debt, "Should correctly identify token0 as debt");

        // Verify incentive is less than input amount (except for very high incentives)
        if (incentives[i] < 10000) {
          assertLt(incentiveAmount, action.inputAmount, "Incentive should be less than input amount");
        }
      }
    }
  }

  /* ============================================================ */
  /* ================ Complex Integration Tests ================ */
  /* ============================================================ */

  function test_integration_multipleScenarios_withTokenOrderVariations() public view {
    // Test various scenarios with both token orders
    bool[2] memory tokenOrders = [true, false]; // isToken0Debt variations
    bool[2] memory pricePositions = [true, false]; // poolPriceAbove variations
    uint256[3] memory incentiveValues = [uint256(0), 500, 2000]; // 0%, 5%, 20%

    for (uint256 i = 0; i < tokenOrders.length; i++) {
      for (uint256 j = 0; j < pricePositions.length; j++) {
        for (uint256 k = 0; k < incentiveValues.length; k++) {
          LQ.Context memory ctx = _createContextWithTokenOrder({
            reserveDen: 120e18,
            reserveNum: 180e18,
            oracleNum: 1e18,
            oracleDen: 1e18,
            poolPriceAbove: pricePositions[j],
            incentiveBps: incentiveValues[k],
            isToken0Debt: tokenOrders[i]
          });

          (bool shouldAct, LQ.Action memory action) = reservePolicy.determineAction(ctx);

          if (shouldAct) {
            // Verify basic action properties
            assertTrue(
              action.dir == LQ.Direction.Expand || action.dir == LQ.Direction.Contract,
              "Should have valid direction"
            );
            assertEq(uint256(action.liquiditySource), uint256(LQ.LiquiditySource.Reserve), "Should use Reserve");
            assertEq(action.incentiveBps, incentiveValues[k], "Should preserve incentive");

            // Verify callback data consistency
            (uint256 incentiveAmount, bool callbackIsToken0Debt) = abi.decode(action.data, (uint256, bool));
            assertEq(callbackIsToken0Debt, tokenOrders[i], "Callback should preserve token order");

            uint256 expectedIncentive = (action.inputAmount * incentiveValues[k]) / 10000;
            assertEq(incentiveAmount, expectedIncentive, "Callback incentive should be correct");

            // Verify token flow consistency with direction and token order
            if (action.dir == LQ.Direction.Expand) {
              // In expansion, debt flows in (inputAmount), collateral flows out
              assertGt(action.inputAmount, 0, "Should have debt input in expansion");
              assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have collateral output in expansion");
            } else {
              // In contraction, collateral flows in (inputAmount), debt flows out
              assertGt(action.inputAmount, 0, "Should have collateral input in contraction");
              assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have debt output in contraction");
            }
          }
        }
      }
    }
  }
}
