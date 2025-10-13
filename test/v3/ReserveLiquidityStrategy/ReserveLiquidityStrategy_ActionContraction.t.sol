// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
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
    addFpmm(0, 100)
  {
    // Pool has excess token0: 200 token0 vs 100 token1 at 1:1 oracle price
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves (debt)
      reserveNum: 100e18, // token1 reserves (collateral)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 100 // 1%
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    assertEq(uint256(action.dir), uint256(LQ.Direction.Contract), "Should contract when pool price below oracle");
    assertEq(action.amount1Out, 0, "No collateral should flow out during contraction");
    assertGt(action.amount0Out, 0, "Debt should flow out during contraction");
    assertGt(action.amountOwedToPool, 0, "Should have collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithDifferentDecimals_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Test with 6 decimal token1 and 18 decimal token0
    // Reserves are normalized to 18 decimals: 100 token1 = 100e18 normalized
    LQ.Context memory ctx = _createContextWithDecimals({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves normalized to 18 decimals
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 100,
      token0Dec: 1e18,
      token1Dec: 1e6
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

  function test_determineAction_whenPoolPriceBelowOracleWithZeroIncentive_shouldReturnCorrectAmounts()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 0
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Y = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * 2)
    // Y = 100e18 / 2 = 50e18 (token0 debt to remove)
    assertEq(action.amount0Out, 50e18, "Should calculate correct debt out");
    // X = Y * (ON/OD) * (1 - i) = 50e18 * (1e18/1e18) * 1 = 50e18 (token1 collateral to add)
    // In contraction: collateral flows in
    assertEq(action.amountOwedToPool, 50e18, "Should calculate correct collateral input amount");
  }

  function test_determineAction_whenPoolPriceBelowOracleWithMaxIncentive_shouldReturnCorrectAmounts()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 200e18, // token0 reserves
      reserveNum: 100e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 10000 // 100%
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Formula: Y = (ON * RD - OD * RN) / (ON * (2 - i))
    // Y = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * 1)
    // Y = 100e18 / 1 = 100e18 (token0 debt to remove)
    assertEq(action.amount0Out, 100e18, "Should calculate correct debt out");
    // X = Y * (ON/OD) * (1 - i) = 100e18 * (1e18/1e18) * 0 = 0 (token1 collateral to add)
    // With 100% incentive, collateral in becomes zero
    assertEq(action.amountOwedToPool, 0, "Should have zero collateral in with 100% incentive");
  }

  /* ============================================================ */
  /* ================= Contraction Formula Tests =============== */
  /* ============================================================ */

  function test_formulaValidation_whenPPLessThanOP_shouldFollowExactFormula()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 0)
  {
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

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    LQ.Action memory action = strategy.determineAction(ctx);

    // Manual calculation:
    // Y = (2e18 * 500e18 - 1e18 * 100e18) / (2e18 * 2)
    // Y = (1000e18 - 100e18) / 4e18 = 900e18 / 4e18 = 225e18 (debt out)
    uint256 expectedY = 225e18;
    assertEq(action.amount0Out, expectedY, "Y calculation should match formula (debt out)");
    // For PP < OP, token1 flows in via amountOwedToPool and token0 flows out

    // X = Y * (ON/OD) * (1 - i) = 225e18 * (2e18/1e18) * 1 = 450e18 (collateral in)
    uint256 expectedX = 450e18;
    assertEq(action.amountOwedToPool, expectedX, "X should equal Y * (ON/OD) * (1 - i)");
  }

  function test_YRelationship_shouldAlwaysHoldForContraction() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test X = Y * (ON/OD) * (1 - i) relationship for contraction (PP < OP)
    uint256[3] memory incentives = [uint256(0), 100, 100]; // Capped at 1%

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(10000e18));

    for (uint256 i = 0; i < incentives.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 450e18, // token0 reserves
        reserveNum: 150e18, // token1 reserves
        oracleNum: 3e18,
        oracleDen: 2e18,
        poolPriceAbove: false,
        incentiveBps: incentives[i]
      });

      LQ.Action memory action = strategy.determineAction(ctx);

      if (action.amount0Out > 0) {
        // X/Y should equal (ON/OD) * (1 - i) (X is amountOwedToPool, Y is amount0Out) within precision limits
        uint256 calculatedRatio = (action.amountOwedToPool * ctx.prices.oracleDen) / action.amount0Out;
        uint256 expectedRatio = (ctx.prices.oracleNum * (10000 - incentives[i])) / 10000;
        // Allow for rounding errors (1 wei difference)
        assertApproxEqAbs(calculatedRatio, expectedRatio, 1, "X/Y ratio should approximately equal (ON/OD) * (1 - i)");
      }
    }
  }
}
