// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
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
    addFpmm(0, 50, 50, 50, 50)
  {
    // Oracle price is 2:1 (2 token1 per 1 token0)
    // Pool has 100 token0 and 100 token1, so it needs more token1
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 2e18, // 2 token1 per token0
      oracleDen: 1e18,
      poolPriceAbove: false, // Pool price below oracle (needs more token1)
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 50,
        protocolIncentiveBpsExpansion: 50, // 0.05% + 0.05% = 1% total expansion incentive
        liquiditySourceIncentiveBpsContraction: 50,
        protocolIncentiveBpsContraction: 50 // 0.05% + 0.05% = 1% total contraction incentive
      })
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
    addFpmm(0, 50, 50, 50, 50)
  {
    // Oracle price is 1:2 (0.5 token1 per 1 token0)
    // Pool has 100 token0 and 100 token1, so it has excess token1
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18, // 0.5 token1 per token0
      oracleDen: 2e18,
      poolPriceAbove: true, // Pool price above oracle (excess token1)
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 50,
        protocolIncentiveBpsExpansion: 50, // 0.5% + 0.5% = 1% total expansion incentive
        liquiditySourceIncentiveBpsContraction: 50,
        protocolIncentiveBpsContraction: 50 // 0.5% + 0.5% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand to remove collateral");
    assertGt(action.amount1Out, 0, "Collateral should flow out");
    assertGt(action.amountOwedToPool, 0, "Debt should flow in");
  }

  /* ============================================================ */
  /* ================= Balance Tests ============================ */
  /* ============================================================ */

  function test_determineAction_whenZeroReserves_shouldNotAct()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 50, 50, 50)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 0, // token0 reserves
      reserveNum: 0, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 50,
        protocolIncentiveBpsExpansion: 50, // 0.5% + 0.5% = 1% total expansion incentive
        liquiditySourceIncentiveBpsContraction: 50,
        protocolIncentiveBpsContraction: 50 // 0.5% + 0.5% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.amount1Out, 0, "No collateral should flow out (amount1)");
    assertEq(action.amount0Out, 0, "No debt should flow out (amount0)");
    assertEq(action.amountOwedToPool, 0, "No input amount should be set");
  }

  function test_determineAction_whenZeroToken0Reserve_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 50, 50, 50)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 0, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 50,
        protocolIncentiveBpsExpansion: 50, // 0.5% + 0.5% = 1% total expansion incentive
        liquiditySourceIncentiveBpsContraction: 50,
        protocolIncentiveBpsContraction: 50 // 0.5% + 0.5% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");
    assertGt(action.amount1Out, 0, "Should remove excess collateral");
  }

  function test_determineAction_whenZeroToken1Reserve_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 50, 50, 50)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 0, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 50,
        protocolIncentiveBpsExpansion: 50, // 0.5% + 0.5% = 1% total expansion incentive
        liquiditySourceIncentiveBpsContraction: 50,
        protocolIncentiveBpsContraction: 50 // 0.5% + 0.5% = 1% total contraction incentive
      })
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
    addFpmm(0, 50, 50, 50, 50)
  {
    // This simulates a real scenario where pool price deviates by 6%

    // Set reserves to create a 6% price difference threshold is 5%
    // Pool price = reserveNum/reserveDen = 106/100 = 1.06
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 106e18, // token1 reserves (6% more to create price difference)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveBpsExpansion: 50,
        protocolIncentiveBpsExpansion: 50, // 0.5% + 0.5% = 1% total expansion incentive
        liquiditySourceIncentiveBpsContraction: 50,
        protocolIncentiveBpsContraction: 50 // 0.5% + 0.5% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Expand, "Should expand");

    // With 6% difference and 1% incentive, amounts should be reasonable
    // with 5% threshold, we rebalance to the threshold 1.05
    // X = (106e18 * 1e18 - 1.05e18 * 100e18) / (1 * 0.99 * 1.05e18 + 1e18)
    // X = 0.490316253983819563e18
    assertApproxEqRel(
      action.amount1Out,
      490316253983819563,
      1e16,
      "Token1 out should be approximately 0.490316253983819563e18"
    );
    // Y = X * 1/1 * (1 - i) = 0.490316253983819563e18 * 0.99 = 0.48541309144398136737e18
    assertApproxEqRel(
      action.amountOwedToPool,
      485413091443981367,
      1e16,
      "Token0 in should be approximately 0.485413091443981367e18"
    );
  }

  function test_determineAction_withMultipleRealisticScenarios_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 50, 50, 50)
  {
    // Test multiple realistic price deviations with appropriate incentives
    uint256[3] memory priceDiffs = [uint256(1051e17), 1071e17, 1101e17]; // 5.1%, 7.1%, 10.1% above

    // total incentives are 0.5%, 1%, 1%
    uint16[3] memory liquiditySourceIncentiveBps = [uint16(25), uint16(50), uint16(50)]; // 0.25%, 0.5%, 0.5% liquidity source incentive
    uint16[3] memory protocolIncentiveBps = [uint16(25), uint16(50), uint16(50)]; // 0.25%, 0.5%, 0.5% protocol incentive

    LQ.Action memory prevAction;
    for (uint256 i = 0; i < priceDiffs.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 100e18,
        reserveNum: priceDiffs[i],
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentives: LQ.RebalanceIncentives({
          liquiditySourceIncentiveBpsExpansion: liquiditySourceIncentiveBps[i],
          protocolIncentiveBpsExpansion: protocolIncentiveBps[i],
          liquiditySourceIncentiveBpsContraction: liquiditySourceIncentiveBps[i],
          protocolIncentiveBpsContraction: protocolIncentiveBps[i]
        })
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
