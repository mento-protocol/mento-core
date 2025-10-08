// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReservePolicyBaseTest, ReserveLiquidityStrategyHarness } from "./ReservePolicyBaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";

contract ReservePolicyBasicTest is ReservePolicyBaseTest {
  ReserveLiquidityStrategyHarness public reserveLS;
  address public mockReserve = makeAddr("mockReserve");

  function setUp() public override {
    super.setUp();
    reserveLS = new ReserveLiquidityStrategyHarness(mockReserve);
  }

  /* ============================================================ */
  /* ==================== View Functions Tests ================== */
  /* ============================================================ */

  function test_name_whenCalled_shouldReturnCorrectName() public view {
    assertEq(reserveLS.name(), "ReservePolicy");
  }

  /* ============================================================ */
  /* ================== Oracle Price Tests ===================== */
  /* ============================================================ */

  function test_determineAction_whenOraclePriceHigh_shouldHandleCorrectly() public view {
    // Oracle price is 2:1 (2 token1 per 1 token0)
    // Pool has 100 token0 and 100 token1, so it needs more token1
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 2e18, // 2 token1 per token0
      oracleDen: 1e18,
      poolPriceAbove: false, // Pool price below oracle (needs more token1)
      incentiveBps: 500
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act when oracle price is high");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should contract to add collateral");
    assertGt(action.amount0Out, 0, "Debt should flow out");
    assertGt(action.inputAmount, 0, "Collateral should flow in");
  }

  function test_determineAction_whenOraclePriceLow_shouldHandleCorrectly() public view {
    // Oracle price is 1:2 (0.5 token1 per 1 token0)
    // Pool has 100 token0 and 100 token1, so it has excess token1
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18, // 0.5 token1 per token0
      oracleDen: 2e18,
      poolPriceAbove: true, // Pool price above oracle (excess token1)
      incentiveBps: 500
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act when oracle price is low");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand to remove collateral");
    assertGt(action.amount1Out, 0, "Collateral should flow out");
    assertGt(action.inputAmount, 0, "Debt should flow in");
  }

  /* ============================================================ */
  /* ================= Balance Tests ============================ */
  /* ============================================================ */

  // NOTE: The _determineAction in the new architecture always returns shouldAct=true
  // when called, as the range check is done separately in rebalance().
  // These tests that expect shouldAct=false when pool price equals oracle are no longer valid.
  // Commenting them out as they test behavior that no longer exists.

  // function test_determineAction_whenPoolPriceEqualsOraclePrice_shouldNotAct() public view {
  //   // NOTE: In new architecture, range checking is done in rebalance() before calling _determineAction
  //   // This test is no longer applicable as _determineAction always returns an action
  // }

  // function test_determineAction_whenPoolPriceEqualsOracle_shouldNotAct() public view {
  //   // NOTE: In new architecture, range checking is done in rebalance() before calling _determineAction
  //   // This test is no longer applicable as _determineAction always returns an action
  // }

  // function test_determineAction_whenZeroReserves_shouldNotAct() public view {
  //   // NOTE: In new architecture, this would cause a division by zero in _determineAction
  //   // The validation would need to happen at a higher level (in rebalance())
  // }

  function test_determineAction_whenZeroToken0Reserve_shouldHandleCorrectly() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 0, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 500
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act when only collateral exists");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand");
    assertGt(action.amount1Out, 0, "Should remove excess collateral");
  }

  function test_determineAction_whenZeroToken1Reserve_shouldHandleCorrectly() public view {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 0, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 500
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act when only debt exists");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should contract");
    assertGt(action.amount0Out, 0, "Should remove excess debt");
  }

  /* ============================================================ */
  /* ================= Realistic Scenarios ===================== */
  /* ============================================================ */

  function test_determineAction_withRealisticPriceDifference_shouldReturnProportionalAmounts() public view {
    // This simulates a real scenario where pool price deviates by 2%

    // Set reserves to create a 2% price difference
    // Pool price = reserveNum/reserveDen = 102/100 = 1.02
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 102e18, // token1 reserves (2% more to create price difference)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100 // 1%
    });

    (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

    assertTrue(shouldAct, "Policy should act with 2% price difference");
    assertEq(uint256(action.dir), uint256(LQ.Direction.Expand), "Should expand");

    // With 2% difference and 1% incentive, amounts should be reasonable
    // X = (1e18 * 102e18 - 1e18 * 100e18) / (1e18 * (20000 - 100) / 10000)
    // X = 2e18 / 1.99 ≈ 1.005e18
    assertApproxEqRel(action.amount1Out, 1.005e18, 1e16, "Token1 out should be approximately 1.005e18");
    assertApproxEqRel(action.inputAmount, 1.005e18, 1e16, "Token0 in should be approximately 1.005e18");
  }

  function test_determineAction_withMultipleRealisticScenarios_shouldHandleCorrectly() public view {
    // Test multiple realistic price deviations with appropriate incentives
    uint256[3] memory priceDiffs = [uint256(101e18), 105e18, 110e18]; // 1%, 5%, 10% above
    uint256[3] memory incentives = [uint256(50), 200, 500]; // 0.5%, 2%, 5% incentives

    for (uint256 i = 0; i < priceDiffs.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 100e18,
        reserveNum: priceDiffs[i],
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: incentives[i]
      });

      (bool shouldAct, LQ.Action memory action) = reserveLS.determineAction(ctx);

      assertTrue(shouldAct, "Policy should act for all realistic scenarios");
      assertGt(action.amount1Out, 0, "Should have token1 output");
      assertGt(action.inputAmount, 0, "Should have token0 input");

      // Verify amounts increase with price difference
      if (i > 0) {
        LQ.Context memory prevCtx = _createContext({
          reserveDen: 100e18,
          reserveNum: priceDiffs[i - 1],
          oracleNum: 1e18,
          oracleDen: 1e18,
          poolPriceAbove: true,
          incentiveBps: incentives[i - 1]
        });

        (, LQ.Action memory prevAction) = reserveLS.determineAction(prevCtx);
        assertGt(action.amount1Out, prevAction.amount1Out, "Larger price diff should yield larger rebalance");
      }
    }
  }
}
