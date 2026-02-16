// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, max-line-length
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ReserveLiquidityStrategy_ActionContractionTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Contraction Tests ======================== */
  /* ============================================================ */

  function test_determineAction_whenPoolPriceBelowOracle_shouldReturnContractAction()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Pool has excess token0: 200 token0 vs 100 token1 at 1:1 oracle price
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves (debt)
      reserveNum: 100e18, // token1 reserves (collateral)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.5025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.5025125628140703% = 1% total contraction incentive
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(action.dir, LQ.Direction.Contract, "Should contract when pool price below oracle");
    assertEq(action.amount1Out, 0, "No collateral should flow out during contraction");
    assertGt(action.amount0Out, 0, "Debt should flow out during contraction");
    assertGt(action.amountOwedToPool, 0, "Should have collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithDifferentDecimals_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 6)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test with 6 decimal token1 and 18 decimal token0
    // Reserves are normalized to 18 decimals: 100 token1 = 100e18 normalized
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves normalized to 18 decimals
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      token0Dec: 1e18,
      token1Dec: 1e6,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.5025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.5025125628140703% = 1% total contraction incentive
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(
      collToken,
      abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)),
      abi.encode(1000e6) // 6 decimal token
    );

    LQ.Action memory action = strategy.determineAction(ctx);

    assertGt(action.amount0Out, 0, "Should have debt output in raw units");
    assertGt(action.amountOwedToPool, 0, "Should have collateral input in raw units");
    // Verify the input is in 6-decimal scale
    assertLt(action.amountOwedToPool, 1e12, "Collateral input should be in 6-decimal scale");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithNotEnoughBalance_shouldReturnCorrectAmounts()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 50, 0.0025e18, 0.002506265664160401e18, 0.0025e18, 0.002506265664160401e18)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 300e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.0025e18,
        protocolIncentiveExpansion: 0.002506265664160401e18, // 0.25% * 0.2506265664160401% = 0.5% total expansion incentive
        liquiditySourceIncentiveContraction: 0.0025e18,
        protocolIncentiveContraction: 0.002506265664160401e18 // 0.25% * 0.2506265664160401% = 0.5% total contraction incentive
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(50e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // Y = (95e16 * 300e18 - 1e18 * 100e18) / (95e16 + 1e18 * (1 - 0.005) * 1e18/1e18)
    // Y = 95115681233933161953
    // X = Y * (ON/OD) * (1 - i) = 95115681233933161953 (token1 collateral to add)
    // but we have at most 50e18 in the reserve, so we clamp collateral to that
    // and calculate deby as 50e18 * 1e18/1e18 * 10000/9950 = 50251256281407035175
    assertEq(action.amount0Out, 50251256281407035175, "Should calculate correct debt out");
    assertEq(action.amountOwedToPool, 50e18, "Should calculate correct collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithZeroIncentive_shouldReturnCorrectAmounts()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0, 0, 0, 0)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0, // 0% total expansion incentive
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0 // 0% total contraction incentive
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // Y = (95e16 * 200e18 - 1e18 * 100e18) / (95e16 + 1e18 * 1 * 1e18/1e18)
    // Y = 46153846153846153846
    assertEq(action.amount0Out, 46153846153846153846, "Should calculate correct debt out");
    // X = Y * (ON/OD) * (1 - i) = 46153846153846153846 (token1 collateral to add)
    // In contraction: collateral flows in
    assertEq(action.amountOwedToPool, 46153846153846153846, "Should calculate correct collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithMaxIncentive_shouldReturnCorrectAmounts()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 50, 50, 50)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 1e18, // 100% incentive
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 1e18, // 100% incentive
        protocolIncentiveContraction: 0
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // Y = (95e16 * 200e18 - 1e18 * 100e18) / (95e16 + 1e18 * 0 * 1e18/1e18)
    // Y = 94736842105263157894
    assertEq(action.amount0Out, 94736842105263157894, "Should calculate correct debt out");
    // X = Y * (ON/OD) * (1 - i) = 0 (token1 collateral to add)
    // With 100% incentive, collateral in becomes zero
    assertEq(action.amountOwedToPool, 0, "Should have zero collateral in with 100% incentive");
  }

  /* ============================================================ */
  /* ================= Contraction Formula Tests =============== */
  /* ============================================================ */

  function test_formulaValidation_whenPPLessThanOP_shouldFollowExactFormula()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0, 0, 0, 0)
  {
    // PP < OP: Y = (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // Test with specific values that give clean division: RN=100, RD=500, ON=2, OD=1, i=0, TN=1.9e18, TD=1e18
    LQ.Context memory ctx = _createContext({
      reserveDen: 500e18, // RD (token0)
      reserveNum: 100e18, // RN (token1)
      oracleNum: 2e18, // ON
      oracleDen: 1e18, // OD
      poolPriceAbove: false,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0,
        protocolIncentiveExpansion: 0, // 0% total expansion incentive
        liquiditySourceIncentiveContraction: 0,
        protocolIncentiveContraction: 0 // 0% total contraction incentive
      })
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Manual calculation:
    // Formula: Y = (TN*RD - TD*RN) / (TN + TD * (1 - i) * ON/OD)
    // Y = (1.9e18 * 500e18 - 1e18 * 100e18) / (1.9e18 + 1e18 * (1 - 0) * 2e18/1e18)
    // Y = 217.948717948717948717e18
    uint256 expectedY = 217948717948717948717;
    assertEq(action.amount0Out, expectedY, "Y calculation should match formula (debt out)");
    // For PP < OP, token1 flows in via amountOwedToPool and token0 flows out

    // X = Y * (ON/OD) * (1 - i) = 217948717948717948717 * 2e18/1e18 * 1 = 435897435897435897434 (collateral in)
    uint256 expectedX = 435897435897435897434;
    assertEq(action.amountOwedToPool, expectedX, "X should equal Y * (ON/OD) * (1 - i)");
  }

  function test_YRelationship_shouldAlwaysHoldForContraction()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test X = Y * (ON/OD) * (1 - i) relationship for contraction (PP < OP)
    uint64[3] memory liquiditySourceIncentive = [uint64(0), uint64(0.005e18), uint64(0.005e18)];
    uint64[3] memory protocolIncentive = [uint64(0), uint64(0.005025125628140703e18), uint64(0.005025125628140703e18)];
    // total incentives are 0%, 1%, 1%

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(10000e18));

    for (uint256 i = 0; i < liquiditySourceIncentive.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 450e18, // token0 reserves
        reserveNum: 150e18, // token1 reserves
        oracleNum: 3e18,
        oracleDen: 2e18,
        poolPriceAbove: false,
        incentives: LQ.RebalanceIncentives({
          liquiditySourceIncentiveExpansion: liquiditySourceIncentive[i],
          protocolIncentiveExpansion: protocolIncentive[i],
          liquiditySourceIncentiveContraction: liquiditySourceIncentive[i],
          protocolIncentiveContraction: protocolIncentive[i]
        })
      });

      LQ.Action memory action = strategy.determineAction(ctx);

      if (action.amount0Out > 0) {
        // X/Y should equal (ON/OD) * (1 - i) (X is amountOwedToPool, Y is amount0Out) within precision limits
        uint256 calculatedRatio = (action.amountOwedToPool * ctx.prices.oracleDen) / action.amount0Out;
        uint256 expectedRatio = (ctx.prices.oracleNum *
          (LQ.combineFees(liquiditySourceIncentive[i], protocolIncentive[i]))) / 1e18;
        // Allow for rounding errors (1 wei difference)
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "X/Y ratio should approximately equal (ON/OD) * (1 - i)");
      }
    }
  }
}
