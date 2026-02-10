// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
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
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test with very small amounts that might cause rounding issues
    LQ.Context memory ctx = _createContext({
      reserveDen: 3, // 3 wei token0
      reserveNum: 5, // 5 wei token1
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.5025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.5025125628140703% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // Should handle small amounts gracefully
    assertGe(action.amount1Out, 0, "Should not have negative collateral out");
    assertGe(action.amountOwedToPool, 0, "Should not have negative input amount");
  }

  function test_determineAction_whenVeryLargeAmounts_shouldNotOverflow()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test with large but realistic amounts (1 trillion tokens with 18 decimals = 1e30)
    uint256 largeAmount = 1e30;

    LQ.Context memory ctx = _createContext({
      reserveDen: largeAmount / 2, // token0 reserves (500B tokens)
      reserveNum: largeAmount, // token1 reserves (1T tokens)
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.5025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.5025125628140703% = 1% total contraction incentive
      })
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
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1, // Very small numerator
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.005e18,
        protocolIncentiveExpansion: 0.005025125628140703e18, // 0.5% * 0.5025125628140703% = 1% total expansion incentive
        liquiditySourceIncentiveContraction: 0.005e18,
        protocolIncentiveContraction: 0.005025125628140703e18 // 0.5% * 0.5025125628140703% = 1% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have token1 out");
    assertGt(action.amountOwedToPool, 0, "Should have input amount");
  }

  function test_determineAction_whenOraclePriceVeryLarge_shouldHandleCorrectly()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 1e18, // token1 reserves (small)
      oracleNum: 1e18,
      oracleDen: 1, // Very small denominator (large price)
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

    assertGt(action.amount0Out, 0, "Should have token0 out");
    assertGt(action.amountOwedToPool, 0, "Should have input amount");
  }

  /* ============================================================ */
  /* ================= Extreme Incentives ====================== */
  /* ============================================================ */

  function test_determineAction_whenIncentiveNearlyMaximum_shouldNotCauseDivisionByZero()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test with incentive very close to maximum (9999 bps = 99.99%, just below 100%)
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 0.999999999e18,
        protocolIncentiveExpansion: 0.999999999e18, // 0.99% * 0.99% = 99.99% total expansion incentive
        liquiditySourceIncentiveContraction: 0.999999999e18,
        protocolIncentiveContraction: 0.999999999e18 // 0.99% * 0.99% = 99.99% total contraction incentive
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    assertGt(action.amount1Out, 0, "Should have valid token1 out");
    // Formula: X = (RN * TD - TN * RD) / (TD + TN * combinedFee * OD / ON*FEE_DENOMINATOR)
    // X = (200e18 * 1e18 - 1.05e18 * 100e18) / (1e18 + (1.05e18 * 1 * 1e18)/( 1e18 * 1e18))
    // X ≈ 94.999999999999999905e18
    assertEq(
      action.amount1Out,
      94999999999999999905,
      "Should calculate correct collateral out with near-max incentive"
    );

    // Y = X * 1/1e18 ≈ 94
    assertEq(action.amountOwedToPool, 94, "Should have very small amount owed with 99.99% incentive");
  }

  function test_edgeCase_whenIncentiveAt10000_shouldReturnZeroAmountOwed()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test with incentive at exactly 10000 bps (100%) - maximum valid value
    // With 100% incentive, Y = X * (1 - 1) = 0
    LQ.Context memory ctx = _createContext({
      reserveDen: 100e18, // token0 reserves
      reserveNum: 200e18, // token1 reserves
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: true,
      incentives: LQ.RebalanceIncentives({
        liquiditySourceIncentiveExpansion: 1e18, // 100% incentive
        protocolIncentiveExpansion: 0,
        liquiditySourceIncentiveContraction: 1e18, // 100% incentive
        protocolIncentiveContraction: 0
      })
    });

    LQ.Action memory action = strategy.determineAction(ctx);

    // Should still calculate collateral out (X)
    assertGt(action.amount1Out, 0, "Should have valid collateral out");
    // But amount owed to pool (Y) should be 0 with 100% incentive
    assertEq(action.amountOwedToPool, 0, "Should have zero amount owed with 100% incentive");
  }

  function test_edgeCase_veryHighIncentive_shouldHandleGracefully()
    public
    fpmmToken0Debt(18, 18)
    addFpmmWithIncentive(0, 100, 0.005e18, 0.005025125628140703e18, 0.005e18, 0.005025125628140703e18)
  {
    // Test various high incentive values (90%-99.9%)
    // total incentives are 90%, 99%, 99.9%
    uint64[3] memory liquiditySourceIncentive = [0.9e18, 0.99e18, 0.999e18];
    uint64[3] memory protocolIncentive = [0.999e18, 0.9999e18, 0.99999e18];

    for (uint256 i = 0; i < liquiditySourceIncentive.length; i++) {
      LQ.Context memory ctx = _createContext({
        reserveDen: 10e18, // token0 reserves
        reserveNum: 20e18, // token1 reserves
        oracleNum: 1e18,
        oracleDen: 1e18,
        poolPriceAbove: true,
        incentives: LQ.RebalanceIncentives({
          liquiditySourceIncentiveExpansion: liquiditySourceIncentive[i],
          protocolIncentiveExpansion: protocolIncentive[i],
          liquiditySourceIncentiveContraction: liquiditySourceIncentive[i],
          protocolIncentiveContraction: protocolIncentive[i]
        })
      });

      LQ.Action memory action = strategy.determineAction(ctx);

      if (action.amount1Out > 0) {
        // Verify no overflow occurred
        assertLe(action.amount1Out, type(uint256).max / 2, "Should not overflow");
        assertLe(action.amountOwedToPool, type(uint256).max / 2, "Should not overflow");

        // Verify Y = X * OD/ON * (1 - i) relationship still holds with high incentives
        if (action.amount1Out > 0) {
          uint256 expectedY = (action.amount1Out *
            ctx.prices.oracleDen *
            (LQ.combineFees(liquiditySourceIncentive[i], protocolIncentive[i]))) /
            (ctx.prices.oracleNum * LQ.FEE_DENOMINATOR);
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
