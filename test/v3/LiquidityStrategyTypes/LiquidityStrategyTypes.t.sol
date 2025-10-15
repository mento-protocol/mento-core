// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { LiquidityStrategyTypesHarness } from "test/utils/harnesses/LiquidityStrategyTypesHarness.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { ILiquidityStrategy } from "contracts/v3/interfaces/ILiquidityStrategy.sol";

contract LiquidityStrategyTypes_Test is Test {
  LiquidityStrategyTypesHarness public harness;

  function setUp() public {
    harness = new LiquidityStrategyTypesHarness();
  }

  /* ============================================================ */
  /* ================= Decimal Scaling Tests ==================== */
  /* ============================================================ */

  function test_scaleFromTo_sameDecimals_shouldReturnSame() public view {
    uint256 amount = 100e18;
    uint256 result = harness.scaleFromTo(amount, 1e18, 1e18);
    assertEq(result, amount);
  }

  function test_scaleFromTo_upscale_shouldScale() public view {
    uint256 amount = 100e6; // 100 USDC (6 decimals)
    uint256 result = harness.scaleFromTo(amount, 1e6, 1e18);
    assertEq(result, 100e18); // Should become 100 with 18 decimals
  }

  function test_scaleFromTo_downscale_shouldScale() public view {
    uint256 amount = 100e18; // 100 with 18 decimals
    uint256 result = harness.scaleFromTo(amount, 1e18, 1e6);
    assertEq(result, 100e6); // Should become 100 with 6 decimals
  }

  function test_to1e18_from6Decimals() public view {
    uint256 amount = 100e6; // 100 USDC
    uint256 result = harness.to1e18(amount, 1e6);
    assertEq(result, 100e18);
  }

  function test_from1e18_to6Decimals() public view {
    uint256 amount18 = 100e18;
    uint256 result = harness.from1e18(amount18, 1e6);
    assertEq(result, 100e6);
  }

  /* ============================================================ */
  /* =============== Rate Conversion Tests ====================== */
  /* ============================================================ */

  function test_convertWithRateScaling_sameDecimalsAndRate() public view {
    uint256 amount = 100e18;
    uint256 result = harness.convertWithRateScaling(amount, 1e18, 1e18, 1e18, 1e18);
    assertEq(result, amount);
  }

  function test_convertWithRateScaling_withPriceChange() public view {
    uint256 amount = 100e18;
    // Convert at 2:1 rate (2 numerator, 1 denominator)
    uint256 result = harness.convertWithRateScaling(amount, 1e18, 1e18, 2e18, 1e18);
    assertEq(result, 200e18);
  }

  function test_convertWithRateScaling_withDecimalsAndPrice() public view {
    uint256 amount = 100e6; // 100 USDC (6 decimals)
    // Convert to 18 decimals at 1:1 rate
    uint256 result = harness.convertWithRateScaling(amount, 1e6, 1e18, 1e18, 1e18);
    assertEq(result, 100e18);
  }

  function test_convertWithRateScalingAndFee_noFee() public view {
    uint256 amount = 100e18;
    // No fee: incentiveNum = incentiveDen
    uint256 result = harness.convertWithRateScalingAndFee(amount, 1e18, 1e18, 1e18, 1e18, 1e18, 1e18);
    assertEq(result, amount);
  }

  function test_convertWithRateScalingAndFee_withFee() public view {
    uint256 amount = 100e18;
    // 10% fee: incentiveNum = 11000, incentiveDen = 10000
    uint256 result = harness.convertWithRateScalingAndFee(amount, 1e18, 1e18, 1e18, 1e18, 11000, 10000);
    assertEq(result, 110e18); // 100 + 10% = 110
  }

  /* ============================================================ */
  /* =================== BPS Functions Tests ==================== */
  /* ============================================================ */

  function test_mulBps_100percent() public view {
    uint256 amount = 100e18;
    uint256 result = harness.mulBps(amount, 10000); // 100% = 10000 bps
    assertEq(result, amount);
  }

  function test_mulBps_50percent() public view {
    uint256 amount = 100e18;
    uint256 result = harness.mulBps(amount, 5000); // 50% = 5000 bps
    assertEq(result, 50e18);
  }

  function test_mulBps_1percent() public view {
    uint256 amount = 100e18;
    uint256 result = harness.mulBps(amount, 100); // 1% = 100 bps
    assertEq(result, 1e18);
  }

  function test_incentiveAmount_shouldCalculateCorrectly() public view {
    uint256 inputAmount = 1000e18;
    uint256 incentiveBps = 50; // 0.5%
    uint256 result = harness.incentiveAmount(inputAmount, incentiveBps);
    assertEq(result, 5e18); // 0.5% of 1000 = 5
  }

  /* ============================================================ */
  /* ================= Constants Tests ========================== */
  /* ============================================================ */

  function test_BASIS_POINTS_DENOMINATOR_shouldBe10000() public view {
    uint256 bps = harness.BASIS_POINTS_DENOMINATOR();
    assertEq(bps, 10000);
  }

  /* ============================================================ */
  /* =============== Context Helper Functions =================== */
  /* ============================================================ */

  function _createContext(
    address token0,
    address token1,
    uint64 token0Dec,
    uint64 token1Dec,
    uint256 oracleNum,
    uint256 oracleDen,
    bool isToken0Debt,
    uint128 incentiveBps
  ) internal pure returns (LQ.Context memory ctx) {
    ctx.pool = address(0x1);
    ctx.token0 = token0;
    ctx.token1 = token1;
    ctx.token0Dec = token0Dec;
    ctx.token1Dec = token1Dec;
    ctx.isToken0Debt = isToken0Debt;
    ctx.incentiveBps = incentiveBps;
    ctx.prices = LQ.Prices({ oracleNum: oracleNum, oracleDen: oracleDen, poolPriceAbove: false, diffBps: 0 });
    ctx.reserves = LQ.Reserves({ reserveNum: 100e18, reserveDen: 100e18 });
  }

  /* ============================================================ */
  /* =========== Context-Dependent Functions Tests ============== */
  /* ============================================================ */

  function test_debtToken_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    address result = harness.debtToken(ctx);
    assertEq(result, token0);
  }

  function test_debtToken_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, false, 50);

    address result = harness.debtToken(ctx);
    assertEq(result, token1);
  }

  function test_collateralToken_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    address result = harness.collateralToken(ctx);
    assertEq(result, token1);
  }

  function test_collateralToken_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, false, 50);

    address result = harness.collateralToken(ctx);
    assertEq(result, token0);
  }

  function test_tokens_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    (address debtToken, address collateralToken) = harness.tokens(ctx);
    assertEq(debtToken, token0);
    assertEq(collateralToken, token1);
  }

  function test_tokens_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, false, 50);

    (address debtToken, address collateralToken) = harness.tokens(ctx);
    assertEq(debtToken, token1);
    assertEq(collateralToken, token0);
  }

  function test_decimals_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e6, 1e18, 1e18, 1e18, true, 50);

    (uint64 debtDec, uint64 collDec) = harness.decimals(ctx);
    assertEq(debtDec, 1e6);
    assertEq(collDec, 1e18);
  }

  function test_decimals_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e6, 1e18, 1e18, false, 50);

    (uint64 debtDec, uint64 collDec) = harness.decimals(ctx);
    assertEq(debtDec, 1e6);
    assertEq(collDec, 1e18);
  }

  /* ============================================================ */
  /* ================== Price Functions Tests =================== */
  /* ============================================================ */

  function test_debtToCollateralPrice_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    // Oracle price: Po = ON/OD = 2/1 = 2
    // This means: token1 = token0 * 2, or 1 token0 (debt) = 2 token1 (collateral)
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 2e18, 1e18, true, 50);

    (uint256 num, uint256 den) = harness.debtToCollateralPrice(ctx);
    // To convert debt to collateral: multiply by num/den = 2/1 = 2
    assertEq(num, 2e18); // oracleNum
    assertEq(den, 1e18); // oracleDen
  }

  function test_debtToCollateralPrice_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    // Oracle price: Po = ON/OD = 1/2 = 0.5
    // This means: token1 = token0 * 0.5, or 1 token1 (debt) = 2 token0 (collateral)
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 2e18, false, 50);

    (uint256 num, uint256 den) = harness.debtToCollateralPrice(ctx);
    // To convert debt to collateral: multiply by num/den = 2/1 = 2
    assertEq(num, 2e18); // oracleDen
    assertEq(den, 1e18); // oracleNum
  }

  function test_collateralToDebtPrice_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    // Oracle price: Po = ON/OD = 2/1 = 2
    // This means: 1 token0 (debt) = 2 token1 (collateral)
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 2e18, 1e18, true, 50);

    (uint256 num, uint256 den) = harness.collateralToDebtPrice(ctx);
    // To convert collateral to debt: multiply by num/den = 1/2 = 0.5
    assertEq(num, 1e18); // oracleDen
    assertEq(den, 2e18); // oracleNum
  }

  function test_collateralToDebtPrice_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    // Oracle price: Po = ON/OD = 1/2 = 0.5
    // This means: 1 token1 (debt) = 2 token0 (collateral)
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 2e18, false, 50);

    (uint256 num, uint256 den) = harness.collateralToDebtPrice(ctx);
    // To convert collateral to debt: multiply by num/den = 1/2 = 0.5
    assertEq(num, 1e18); // oracleNum
    assertEq(den, 2e18); // oracleDen
  }

  /* ============================================================ */
  /* ================= Conversion Functions Tests =============== */
  /* ============================================================ */

  function test_convertToDebtToken_sameDecimals_1to1Price() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    uint256 collateralAmount = 100e18;
    uint256 result = harness.convertToDebtToken(ctx, collateralAmount);
    assertEq(result, 100e18);
  }

  function test_convertToDebtToken_withPriceConversion() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    // Po = ON/OD = 2, so 1 debt = 2 collateral
    // Therefore: 100 collateral = 50 debt
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 2e18, 1e18, true, 50);

    uint256 collateralAmount = 100e18;
    uint256 result = harness.convertToDebtToken(ctx, collateralAmount);
    assertEq(result, 50e18);
  }

  function test_convertToDebtToken_withDecimalsAndPrice() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    // Debt (token0) has 6 decimals, collateral (token1) has 18 decimals
    // Price: 1:1
    // 100 collateral (18 dec) = 100 debt (6 dec)
    LQ.Context memory ctx = _createContext(token0, token1, 1e6, 1e18, 1e18, 1e18, true, 50);

    uint256 collateralAmount = 100e18; // 100 with 18 decimals
    uint256 result = harness.convertToDebtToken(ctx, collateralAmount);
    assertEq(result, 100e6); // 100 with 6 decimals
  }

  function test_convertToDebtWithFee_custom() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    uint256 collateralAmount = 100e18;
    // Custom 10% fee
    uint256 result = harness.convertToDebtWithFee_custom(ctx, collateralAmount, 11000, 10000);
    assertEq(result, 110e18);
  }

  function test_convertToCollateralWithFee_custom() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    uint256 debtAmount = 100e18;
    // Custom: subtract 10%
    uint256 result = harness.convertToCollateralWithFee_custom(ctx, debtAmount, 9000, 10000);
    assertEq(result, 90e18);
  }

  function test_conversion_roundTrip_debtToCollateralAndBack() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 0); // No fee

    uint256 originalDebt = 100e18;

    // Convert debt to collateral (uses debtToCollateralPrice internally)
    uint256 collateral = harness.convertToCollateralWithFee_custom(ctx, originalDebt, 1e18, 1e18);

    // Convert back to debt
    uint256 finalDebt = harness.convertToDebtToken(ctx, collateral);

    assertEq(finalDebt, originalDebt);
  }

  function test_conversion_withDifferentTokenOrders() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);

    // Test with token0 as debt: Po = ON/OD = 2, so 1 debt = 2 collateral
    LQ.Context memory ctx1 = _createContext(token0, token1, 1e18, 1e18, 2e18, 1e18, true, 0);
    uint256 result1 = harness.convertToDebtToken(ctx1, 100e18);

    // Test with token1 as debt: Po = ON/OD = 0.5, so 1 debt = 2 collateral
    LQ.Context memory ctx2 = _createContext(token0, token1, 1e18, 1e18, 1e18, 2e18, false, 0);
    uint256 result2 = harness.convertToDebtToken(ctx2, 100e18);

    // Both should convert 100 collateral to 50 debt (since 1 debt = 2 collateral in both cases)
    assertEq(result1, 50e18);
    assertEq(result2, 50e18);
  }

  /* ============================================================ */
  /* ================= Action Creation Tests ==================== */
  /* ============================================================ */

  function test_newExpansion_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    uint256 expansionAmount = 100e18; // Debt to add
    uint256 collateralPayed = 50e18; // Collateral to receive

    LQ.Action memory action = harness.newExpansion(ctx, expansionAmount, collateralPayed);

    assertEq(uint(action.dir), uint(LQ.Direction.Expand));
    assertEq(action.amountOwedToPool, expansionAmount);
    assertEq(action.amount0Out, 0); // No debt out
    assertEq(action.amount1Out, collateralPayed); // Collateral out (token1)
  }

  function test_newExpansion_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, false, 50);

    uint256 expansionAmount = 100e18;
    uint256 collateralPayed = 50e18;

    LQ.Action memory action = harness.newExpansion(ctx, expansionAmount, collateralPayed);

    assertEq(uint(action.dir), uint(LQ.Direction.Expand));
    assertEq(action.amountOwedToPool, expansionAmount);
    assertEq(action.amount0Out, collateralPayed); // Collateral out (token0)
    assertEq(action.amount1Out, 0); // No debt out
  }

  function test_newContraction_whenToken0IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, true, 50);

    uint256 contractionAmount = 100e18; // Debt to receive from pool
    uint256 collateralReceived = 50e18; // Collateral to send to pool

    LQ.Action memory action = harness.newContraction(ctx, contractionAmount, collateralReceived);

    assertEq(uint(action.dir), uint(LQ.Direction.Contract));
    assertEq(action.amountOwedToPool, collateralReceived);
    assertEq(action.amount0Out, contractionAmount);
    assertEq(action.amount1Out, 0);
  }

  function test_newContraction_whenToken1IsDebt() public view {
    address token0 = address(0x100);
    address token1 = address(0x200);
    LQ.Context memory ctx = _createContext(token0, token1, 1e18, 1e18, 1e18, 1e18, false, 50);

    uint256 contractionAmount = 100e18;
    uint256 collateralReceived = 50e18;

    LQ.Action memory action = harness.newContraction(ctx, contractionAmount, collateralReceived);

    assertEq(uint(action.dir), uint(LQ.Direction.Contract));
    assertEq(action.amountOwedToPool, collateralReceived);
    assertEq(action.amount0Out, 0);
    assertEq(action.amount1Out, contractionAmount);
  }

  /* ============================================================ */
  /* =================== Complex Scenarios ====================== */
  /* ============================================================ */

  function test_conversion_roundTrip_shouldBeAccurate() public view {
    uint256 original = 100e6; // 100 USDC

    // Convert to 18 decimals
    uint256 scaled = harness.scaleFromTo(original, 1e6, 1e18);

    // Convert back to 6 decimals
    uint256 result = harness.scaleFromTo(scaled, 1e18, 1e6);

    assertEq(result, original);
  }

  function test_conversion_withPriceAndFee() public view {
    uint256 amount = 100e6; // 100 USDC (6 decimals)

    // Convert to 18 decimals, with 2:1 price, and 1% fee
    // Expected: (100 * 2 * 1e18 * 10100) / (1e6 * 1 * 10000)
    // = (2,020,000,000,000,000,000,000) / (10,000,000,000)
    // = 202e18
    uint256 result = harness.convertWithRateScalingAndFee(
      amount,
      1e6, // from 6 decimals
      1e18, // to 18 decimals
      2e18, // price numerator (2:1)
      1e18, // price denominator
      10100, // 1% fee (10000 + 100)
      10000 // fee denominator
    );

    assertEq(result, 202e18);
  }
}
