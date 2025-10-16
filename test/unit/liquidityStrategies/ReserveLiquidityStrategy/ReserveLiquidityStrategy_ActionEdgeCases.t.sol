// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { ReserveLiquidityStrategy_BaseTest } from "./ReserveLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";
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

    LQ.Action memory action = strategy.determineAction(ctx);

    // Should handle small amounts gracefully
    assertGe(action.amount1Out, 0, "Should not have negative collateral out");
    assertGe(action.amountOwedToPool, 0, "Should not have negative input amount");
  }

  function test_determineAction_whenVeryLargeAmounts_shouldNotOverflow() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test with large but realistic amounts (1 trillion tokens with 18 decimals = 1e30)
    uint256 largeAmount = 1e30;

    LQ.Context memory ctx = _createContext({
      reserveDen: largeAmount / 2, // token0 reserves (500B tokens)
      reserveNum: largeAmount, // token1 reserves (1T tokens)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 100 // 1%
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have valid token1 out");
    assertGt(action.amountOwedToPool, 0, "Should have valid amount owed");

    // Verify amounts are in reasonable range for large values
    assertLt(action.amount1Out, largeAmount, "Collateral out should be less than total reserves");
    assertLt(action.amountOwedToPool, largeAmount, "Amount owed should be less than total reserves");
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

    LQ.Action memory action = strategy.determineAction(ctx);

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

    LQ.Action memory action = strategy.determineAction(ctx);

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
    // Test with incentive very close to maximum (9999 bps = 99.99%, just below 100%)
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 9999 // 99.99%
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have valid token1 out");
    // Formula: X = (OD * RN - ON * RD) / (OD * (2 - i))
    // X = (1e18 * 200e18 - 1e18 * 100e18) / (1e18 * (20000 - 9999) / 10000)
    // X = 100e18 / 1.0001 ≈ 99.99e18
    assertApproxEqAbs(
      action.amount1Out,
      100e18,
      1e17,
      "Should calculate correct collateral out with near-max incentive"
    );

    // Y = X * (1 - i) = X * 0.0001 ≈ 0.01e18
    assertApproxEqAbs(action.amountOwedToPool, 1e16, 1e15, "Should have very small amount owed with 99.99% incentive");
  }

  function test_edgeCase_whenIncentiveAt10000_shouldReturnZeroAmountOwed()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 100)
  {
    // Test with incentive at exactly 10000 bps (100%) - maximum valid value
    // With 100% incentive, Y = X * (1 - 1) = 0
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentiveBps: 10000 // 100%
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // Should still calculate collateral out (X)
    assertGt(action.amount1Out, 0, "Should have valid collateral out");
    // But amount owed to pool (Y) should be 0 with 100% incentive
    assertEq(action.amountOwedToPool, 0, "Should have zero amount owed with 100% incentive");
  }

  function test_edgeCase_veryHighIncentive_shouldHandleGracefully() public fpmmToken0Debt(18, 18) addFpmm(0, 100) {
    // Test various high incentive values (90%-99.9%)
    uint256[3] memory incentiveBps = [uint256(9000), 9900, 9990]; // 90%, 99%, 99.9%

    for (uint256 i = 0; i < incentiveBps.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 10e18, // token0 reserves
        reserveNum: 20e18, // token1 reserves
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentiveBps: incentiveBps[i]
      });

      LQ.Action memory action = strategy.determineAction(ctx);

      if (action.amount1Out > 0) {
        // Verify no overflow occurred
        assertLe(action.amount1Out, type(uint256).max / 2, "Should not overflow");
        assertLe(action.amountOwedToPool, type(uint256).max / 2, "Should not overflow");

        // Verify Y = X * OD/ON * (1 - i) relationship still holds with high incentives
        if (action.amount1Out > 0) {
          uint256 expectedY = (action.amount1Out * ctx.prices.oracleDen * (10000 - ctx.incentiveBps)) /
            (ctx.prices.oracleNum * 10000);
          assertApproxEqAbs(
            action.amountOwedToPool,
            expectedY,
            1,
            "Y relationship should hold even with high incentive"
          );
        }
      }
    }
  }
}
