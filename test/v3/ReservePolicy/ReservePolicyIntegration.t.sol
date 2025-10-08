// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { ReservePolicyBaseTest, ReserveLiquidityStrategyHarness } from "./ReservePolicyBaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract ReservePolicyIntegrationTest is ReservePolicyBaseTest {
  ReserveLiquidityStrategyHarness public reserveLS;
  address public mockReserve = makeAddr("mockReserve");

  function setUp() public override {
    super.setUp();
    reserveLS = new ReserveLiquidityStrategyHarness(mockReserve);
  }

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
      poolPriceAbove: true, // PP = 200/100 = 2, OP = 1/1 = 1, so PP > OP
      incentiveBps: 500,
      isToken0Debt: false // token1 is debt
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with reversed token order");
    // When token1 is debt and PP > OP, we need to expand (remove excess debt)
    // Pool has 200 debt (token1) vs 100 collateral (token0) at 1:1 oracle, so pool price > oracle
    // This means too much debt relative to collateral, so we expand (remove debt, add collateral)
    assertEq(
      uint256(action.dir),
      uint256(LQ.Direction.Expand),
      "Should expand when pool price above oracle"
    );
    assertEq(action.amount0Out, 0, "No collateral (token0) should flow out");
    assertGt(action.amount1Out, 0, "Should have debt (token1) flowing out");
    assertGt(action.inputAmount, 0, "Should have collateral input amount");
  }

  function test_determineAction_whenToken0IsCollateral_shouldHandleExpansionCorrectly() public view {
    // Test expansion scenario when token0 is collateral (token1 is debt)
    // NOTE: poolPriceAbove requires reserveNum > reserveDen when oracle is 1:1
    // But this scenario has reserveNum < reserveDen, so poolPriceAbove should be FALSE
    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: 200e18, // token0 (collateral) reserves
      reserveNum: 100e18, // token1 (debt) reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false, // PP = 100/200 = 0.5, OP = 1/1 = 1, so PP < OP
      incentiveBps: 500,
      isToken0Debt: false // token1 is debt
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act");
    // When PP < OP and isToken0Debt=false, _handlePoolPriceBelow is called
    // which calls _buildExpansionAction to add debt (token1) and remove collateral (token0)
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand");
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

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract), "Should contract when excess debt");
    assertEq(action.amount0Out, 0, "No collateral (token0) should flow out");
    assertGt(action.amount1Out, 0, "Should have debt (token1) flowing out");
    assertGt(action.inputAmount, 0, "Should have collateral input amount");
  }

  /* ============================================================ */
  /* ================ Callback Data Tests ====================== */
  /* ============================================================ */

  // NOTE: Callback data tests are not applicable in the new architecture
  // The Action struct no longer has a `data` field for callback encoding
  // Callback data was used in the old LiquidityController pattern

  // function test_determineAction_callbackDataEncoding_shouldBeCorrect() public view {
  //   // NOTE: Action struct no longer has a `data` field in new architecture
  //   // Skipping this test as callback data is not part of the new design
  // }

  /* ============================================================ */
  /* ================ Complex Integration Tests ================ */
  /* ============================================================ */

  function test_integration_multipleScenarios_withTokenOrderVariations() public view {
    // Test various scenarios with both token orders
    // NOTE: poolPriceAbove must match actual reserves: reserveNum/reserveDen vs oracleNum/oracleDen
    // With reserves 180/120 = 1.5 and oracle 1/1 = 1, poolPrice > oracle, so poolPriceAbove = true
    bool[2] memory tokenOrders = [true, false]; // isToken0Debt variations
    uint256[3] memory incentiveValues = [uint256(0), 500, 2000]; // 0%, 5%, 20%

    for (uint256 i = 0; i < tokenOrders.length; i++) {
      for (uint256 k = 0; k < incentiveValues.length; k++) {
        LQ.Context memory ctx = _createContextWithTokenOrder({
          reserveDen: 120e18,
          reserveNum: 180e18,
          oracleNum: 1e18,
          oracleDen: 1e18,
          poolPriceAbove: true, // 180/120 = 1.5 > 1/1 = 1
          incentiveBps: incentiveValues[k],
          isToken0Debt: tokenOrders[i]
        });

        (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

        if (shouldAct) {
          // Verify basic action properties
          assertTrue(
            action.dir == LQ.Direction.Expand,
            "Should have valid direction"
          );

          // Verify token flows
          assertGt(action.inputAmount, 0, "Should have input amount");
          assertTrue(action.amount0Out > 0 || action.amount1Out > 0, "Should have token output");
        }
      }
    }
  }
}
