// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract ReserveLiquidityStrategy_ActionEdgeCasesTest is ReserveLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ================= Small and Large Amounts ================= */
  /* ============================================================ */

  function test_determineAction_whenVerySmallAmounts_shouldHandleRounding()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Test with very small amounts that might cause rounding issues
    LQ.Context memory ctx = _createContext({
      reserveDen: 3, // 3 wei token0
      reserveNum: 5, // 5 wei token1
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    // Should handle small amounts gracefully
    assertGe(action.amount1Out, 0, "Should not have negative collateral out");
    assertGe(action.amountOwedToPool, 0, "Should not have negative input amount");
  }

  function test_determineAction_whenVeryLargeAmounts_shouldNotOverflow() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test with large amounts close to uint256 max
    uint256 largeAmount = type(uint128).max; // Use uint128 max to avoid overflow in calculations

    LQ.Context memory ctx = _createContext({
      reserveDen: largeAmount / 2, // token0 reserves
      reserveNum: largeAmount, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have valid token1 out");
    assertGt(action.amountOwedToPool, 0, "Should have valid input amount");
  }

  /* ============================================================ */
  /* ================= Extreme Oracle Prices =================== */
  /* ============================================================ */

  function test_determineAction_whenOraclePriceVerySmall_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1, // Very small numerator
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have token1 out");
    assertGt(action.amountOwedToPool, 0, "Should have input amount");
  }

  function test_determineAction_whenOraclePriceVeryLarge_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 1e18, // token1 reserves (small)
      oracleNum: 1e18,
      oracleDen: 1, // Very small denominator (large price)
      poolPriceAbove: false,
      incentiveBps: 100
    });

    // Mock reserve to have collateral balance for contraction
    vm.mockCall(collToken, abi.encodeWithSelector(IERC20.balanceOf.selector, address(reserve)), abi.encode(1000e18));

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertGt(action.amount0Out, 0, "Should have token0 out");
    assertGt(action.amountOwedToPool, 0, "Should have input amount");
  }

  /* ============================================================ */
  /* ================= Extreme Incentives ====================== */
  /* ============================================================ */

  function test_determineAction_whenIncentiveNearlyMaximum_shouldNotCauseDivisionByZero()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Test with incentive very close to maximum (near 20000 bps which would cause division by zero)
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 19999 // Just below 20000 which would cause division by zero
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have valid token1 out");
    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * 1 / 10000)
    // X = 100e18 * 10000 = 1000000e18
    assertEq(action.amount1Out, 1000000e18, "Should calculate extreme collateral out");
  }

  function test_edgeCase_whenIncentiveAt20000_shouldReturnZero() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test with incentive at exactly 20000 bps (200%) - theoretical maximum
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 20000 // Exactly 20000 would cause division by zero
    });

    (, LQ.Action memory action) = strategy.determineAction(ctx);

    // When denominator is 0, the function should return no action
    assertEq(action.amount0Out, 0, "Should have zero output");
    assertEq(action.amount1Out, 0, "Should have zero output");
  }

  function test_edgeCase_verySmallDenominator_shouldHandleGracefully() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test various incentive values that create very small denominators
    uint256[3] memory incentiveBps = [uint256(19990), 19995, 19998];

    for (uint256 i = 0; i < incentiveBps.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 10e18, // token0 reserves
        reserveNum: 20e18, // token1 reserves
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: incentiveBps[i]
      });

      (, LQ.Action memory action) = strategy.determineAction(ctx);

      if (action.amount1Out > 0) {
        // Verify no overflow occurred
        assertLe(action.amount1Out, type(uint256).max / 2, "Should not overflow");
        assertLe(action.amountOwedToPool, type(uint256).max / 2, "Should not overflow");

        // Verify Y = X * OD/ON relationship still holds
        if (action.amount1Out > 0) {
          uint256 calculatedY = (action.amount1Out * ctx.prices.oracleDen) / ctx.prices.oracleNum;
          assertEq(action.amountOwedToPool, calculatedY, "Y relationship should hold even with small denominator");
        }
      }
    }
  }
}
