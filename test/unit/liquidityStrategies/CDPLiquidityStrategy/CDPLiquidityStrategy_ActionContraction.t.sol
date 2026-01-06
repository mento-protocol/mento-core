// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable max-line-length
pragma solidity ^0.8;

import { CDPLiquidityStrategy_BaseTest } from "./CDPLiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/libraries/LiquidityStrategyTypes.sol";

contract CDPLiquidityStrategy_ActionContractionTest is CDPLiquidityStrategy_BaseTest {
  function setUp() public override {
    super.setUp();
  }

  /* ============================================================ */
  /* ============== Contraction target liquidity ================ */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceBelowAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice()
    public
    fpmmToken0Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 7_089_031 * 1e18; // brl.m 1.3Mio in $
    uint256 reserve1 = 1_000_000 * 1e6; // usd.m 1Mio in $

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 1e18, // USD/BRL rate
      oracleDen: 5476912800000000000,
      poolPriceAbove: false,
      incentiveBps: 50,
      isToken0Debt: true
    });

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18, ctx); // 0.25% resulting in redemption fee being 0.25% + 0.25% = 0.5%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);

    // amount out in token 0 := (ON*RD - OD*RN)/(ON*(2-i)) = 808079.298245614035087719
    uint256 expectedAmount0Out = 808079298245614035086719;
    uint256 expectedAmount1Out = 0;

    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption
  }

  function test_determineAction_whenToken1DebtPoolPriceAboveAndRedemptionFeeEqualToIncentive_shouldContractAndBringPriceBackToOraclePrice()
    public
    fpmmToken1Debt(6, 18)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 10_000_000 * 1e18; // usd.m
    uint256 reserve1 = 14_500_000 * 1e6; // chf.m

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0,
      reserveNum: reserve1 * 1e12,
      oracleNum: 1e18,
      oracleDen: 1242930830000000000,
      poolPriceAbove: true,
      incentiveBps: 50,
      isToken0Debt: false
    });

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0025 * 1e18, ctx); // 0.25% resulting in redemption fee being 0.25% + 0.25% = 0.5%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);

    uint256 expectedAmount0Out = 0;
    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 3_235_338.342946
    uint256 expectedAmount1Out = 3235338341946;

    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption
  }

  /* ============================================================ */
  /* ============== Contraction non-target liquidity ============ */
  /* ============================================================ */

  function test_determineAction_whenToken0DebtPoolPriceBelowAndRedemptionFeeLessIncentive_shouldContractAndBringPriceAboveOraclePrice()
    public
    fpmmToken0Debt(6, 18)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 10_956_675_007 * 1e6; // ngnm 7.5 mio in $
    uint256 reserve1 = 6_000_000 * 1e18; // usdm 6 mio in $

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0 * 1e12, // reserve token 0 ngnm
      reserveNum: reserve1, // reserve token 1 usdm
      oracleNum: 684510000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50,
      isToken0Debt: true
    });

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0015 * 1e18, ctx); // 0.15% resulting in redemption fee being 0.25% + 0.15% = 0.4%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);

    // amount out in token 0 := (ON*RD - OD*RN)/(ON*(2-i)) = 1_098_386_357.591375
    uint256 expectedAmount0Out = 1098386357591375;
    uint256 expectedAmount1Out = 0;

    assertEq(action.dir, LQ.Direction.Contract);

    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption
  }

  function test_determineAction_whenToken1DebtPoolPriceAboveAndRedemptionFeeLessIncentive_shouldContractAndBringPriceBelowOraclePrice()
    public
    fpmmToken1Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 555_555 * 1e6; // 555555 usd.m
    uint256 reserve1 = 43_629_738 * 1e18; // php.m 750k in $

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0 * 1e12, // reserve token 0 usd.m
      reserveNum: reserve1, // reserve token 1 php.m
      oracleNum: 1e18,
      oracleDen: 17190990000000000,
      poolPriceAbove: true,
      incentiveBps: 50,
      isToken0Debt: false
    });

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.001 * 1e18, ctx); // 0.1% resulting in redemption fee being 0.25% + 0.1% = 0.35%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);

    uint256 expectedAmount0Out = 0;
    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 5_670_726.837208791926748374
    uint256 expectedAmount1Out = 5670726837208791926748374;

    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption
  }

  function test_determineAction_whenToken0DebtPoolPriceBelowAndRedemptionFeeGreaterIncentive_shouldContractAndBringPriceCloserToOraclePrice()
    public
    fpmmToken0Debt(6, 18)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 10_956_675_007 * 1e6; // ngnm 7.5 mio in $
    uint256 reserve1 = 6_000_000 * 1e18; // usdm 6 mio in $

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0 * 1e12, // reserve token 0 ngnm
      reserveNum: reserve1, // reserve token 1 usdm
      oracleNum: 684510000000000,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50,
      isToken0Debt: true
    });

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.0035 * 1e18, ctx); // 0.35% resulting in redemption fee being 0.25% + 0.35% = 0.6%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);

    // target amount out in token 0 := (ON*RD - OD*RN)/(ON*(2-i)) = 1_098_386_357.591375
    // since redemption fee for target amount is greater than incentive.
    // we will redeem an amount that results in a redemption fee equal to incentive.
    // maximum amount that can be redeemed is: totalSupply * redemptionBeta * (incentive - decayedBaseFee) =
    // = 313824673597535714 * 1 * (0.005 - 0.0025) =  784_561_683.993839
    // Note: reduced by REDEMPTION_ROUNDING_BUFFER (1000 wei) to account for multi-trove rounding losses
    uint256 expectedAmount0Out = 784561683992839;
    uint256 expectedAmount1Out = 0;

    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption
  }

  function test_determineAction_whenToken1DebtPoolPriceAboveAndRedemptionFeeGreaterIncentive_shouldContractAndBringPriceCloserToOraclePrice()
    public
    fpmmToken1Debt(18, 6)
    addFpmm(0, 50, 9000)
  {
    uint256 reserve0 = 555_555 * 1e6; // 555555 usd.m
    uint256 reserve1 = 43_629_738 * 1e18; // php.m 750k in $

    LQ.Context memory ctx = _createContextWithTokenOrder({
      reserveDen: reserve0 * 1e12, // reserve token 0 usd.m
      reserveNum: reserve1, // reserve token 1 php.m
      oracleNum: 1e18,
      oracleDen: 17190990000000000,
      poolPriceAbove: true,
      incentiveBps: 50,
      isToken0Debt: false
    });

    mockRedemptionRateWithDecay(0.0025 * 1e18); // 0.25%
    uint256 totalSupply = calculateTargetSupply(0.005 * 1e18, ctx); // 0.5% resulting in redemption fee being 0.25% + 0.5% = 0.75%
    setDebtTokenTotalSupply(totalSupply);

    LQ.Action memory action = strategy.determineAction(ctx);

    uint256 expectedAmount0Out = 0;
    // amount out in token 1 := (OD*RN - ON*RD)/(OD*(2-i)) = 5_670_726.837208791926748374
    // since redemption fee for target amount is greater than incentive.
    // we will redeem an amount that results in a redemption fee equal to incentive.
    // maximum amount that can be redeemed is: totalSupply * redemptionBeta * (incentive - decayedBaseFee) =
    // = 1134145367441758385349674800 * 1 * (0.005 - 0.0025) =  2_835_363.418604395963374187
    // Note: reduced by REDEMPTION_ROUNDING_BUFFER (1000 wei) to account for multi-trove rounding losses
    uint256 expectedAmount1Out = 2835363418604395963373187;

    assertEq(action.dir, LQ.Direction.Contract);
    assertEq(action.amount0Out, expectedAmount0Out);
    assertEq(action.amount1Out, expectedAmount1Out);
    assertEq(action.amountOwedToPool, 0); // expected to always be 0 because can't calculate precise amount of collateral to receive from redemption
  }

  /* ============================================================ */
  /* ================ Redemption Fee Edge Cases ================ */
  /* ============================================================ */

  function test_determineAction_whenRedemptionFeeExceedsIncentive_shouldRevert()
    public
    fpmmToken0Debt(18, 18)
    addFpmm(0, 50, 9000)
  {
    // Setup: Redemption fee is higher than incentive
    LQ.Context memory ctx = _createContext({
      reserveDen: 1_500_000e18,
      reserveNum: 1_000_000e18,
      oracleNum: 1e18,
      oracleDen: 1e18,
      poolPriceAbove: false,
      incentiveBps: 50 // 0.5% incentive
    });

    // Mock redemption rate at 0.6% (higher than 0.5% incentive)
    mockRedemptionRateWithDecay(0.006 * 1e18);

    setDebtTokenTotalSupply(1_000_000_000e18);
    mockCollateralRegistryOracleRate(ctx.prices.oracleNum, ctx.prices.oracleDen);

    // Should revert because redemption fee exceeds incentive
    vm.expectRevert();
    strategy.determineAction(ctx);
  }
}
