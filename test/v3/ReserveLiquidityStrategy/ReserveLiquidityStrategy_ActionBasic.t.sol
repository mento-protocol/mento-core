// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ReserveLiquidityStrategy_ActionBasicTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================== Oracle Price Tests ===================== */
  /* ============================================================ */

  function test_determineAction_whenOraclePriceHigh_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Oracle price is 2:1 (2 token1 per 1 token0)
    // Pool has 100 token0 and 100 token1, so it needs more token1
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 2e18, // 2 token1 per token0
      oracleDen: 1e18,
      poolPriceAbove: false, // Pool price below oracle (needs more token1)
      incentiveBps: 100
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract to add collateral");
    assertGt(action.amount0Out, 0, "Debt should flow out");
    assertGt(action.amountOwedToPool, 0, "Collateral should flow in");
  }

  function test_determineAction_whenOraclePriceLow_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Oracle price is 1:2 (0.5 token1 per 1 token0)
    // Pool has 100 token0 and 100 token1, so it has excess token1
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18, // 0.5 token1 per token0
      oracleDen: 2e18,
      poolPriceAbove: true, // Pool price above oracle (excess token1)
      incentiveBps: 100
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand to remove collateral");
    assertGt(action.amount1Out, 0, "Collateral should flow out");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in");
  }

  /* ============================================================ */
  /* ================= Balance Tests ============================ */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceEqualsOraclePrice_shouldNotAct()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Scenario: Pool price equals oracle price
    // With 100 token0 and 100 token1 at 1:1 oracle price, pool price = oracle price
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false, // Pool price equals oracle price, not above
      incentiveBps: 100
    });

    // Mock reserve balance (even though no action should occur)
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.amount1Out, 0, "No token1 should flow out");
    assertEq(action.amount0Out, 0, "No token0 should flow out");
    assertEq(action.amountOwedToPool, 0, "No input amount should be set");
  }

  function test_determineAction_whenPoolPriceEqualsOracle_shouldNotAct() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Pool price equals oracle price: 100 token0 vs 100 token1 at 1:1 oracle price
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18,
      reserveNum: 100e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 100
    });

    // Mock reserve balance (even though no action should occur)
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.amount0Out, 0, "No token0 should flow out");
    assertEq(action.amountOwedToPool, 0, "No input amount should be set");
  }

  function test_determineAction_whenZeroReserves_shouldNotAct() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    LQ.Context memory ctx = _createContext({
      reserveDen: 0, // token0 reserves
      reserveNum: 0, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.amount1Out, 0, "No collateral should flow out (amount1)");
    assertEq(action.amount0Out, 0, "No debt should flow out (amount0)");
    assertEq(action.amountOwedToPool, 0, "No input amount should be set");
  }

  function test_determineAction_whenZeroToken0Reserve_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 0, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertGt(action.amount1Out, 0, "Should remove excess collateral");
  }

  function test_determineAction_whenZeroToken1Reserve_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 0, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 100
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract");
    assertGt(action.amount0Out, 0, "Should remove excess debt");
  }

  /* ============================================================ */
  /* ================= Realistic Scenarios ===================== */
  /* ============================================================ */

  function test_determineAction_withRealisticPriceDifference_shouldReturnProportionalAmounts()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
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

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");

    // With 2% difference and 1% incentive, amounts should be reasonable
    // X = (1e18 * 102e18 - 1e18 * 100e18) / (1e18 * (20000 - 100) / 10000)
    // X = 2e18 / 1.99 ≈ 1.005e18
    assertApproxEqRel(action.amount1Out, 1.005e18, 1e16, "Token1 out should be approximately 1.005e18");
    assertApproxEqRel(action.amountOwedToPool, 1.005e18, 1e16, "Token0 in should be approximately 1.005e18");
  }

  function test_determineAction_withMultipleRealisticScenarios_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Test multiple realistic price deviations with appropriate incentives
    uint256[3] memory priceDiffs = [uint256(101e18), 105e18, 110e18]; // 1%, 5%, 10% above
    uint256[3] memory incentives = [uint256(50), 100, 100]; // 0.5%, 1%, 1% incentives (capped at 1%)

    LQ.Action memory prevAction;
    for (uint256 i = 0; i < priceDiffs.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 100e18,
        reserveNum: priceDiffs[i],
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: incentives[i]
      });

      LQ.Action memory action = strategy.determineAction(ctx);

      assertGt(action.amount1Out, 0, "Should have token1 output");
      assertGt(action.amountOwedToPool, 0, "Should have token0 input");

      // Verify amounts increase with price difference
      if (i > 0) {
        assertGt(action.amount1Out, prevAction.amount1Out, "Larger price diff should yield larger rebalance");
      }
      prevAction = action;
    }
  }
}
