// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";

abstract contract CDPFPMM_BaseTest is
  TokenDeployer,
  OracleAdapterDeployer,
  LiquidityStrategyDeployer,
  FPMMDeployer,
  LiquityDeployer
{
  address reserveMultisig = makeAddr("reserveMultisig");

  function test_expansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 10_000_000e18); // EUR.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(5_000_000e18, false);

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);

    // amountGivenToPool: 4500000000000000000000000
    // debt = 3_000_000e18 + 4500000000000000000000000
    // coll = 10_000_000e18 - 4500000000000000000000000 / 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 4500000000000000000000000);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256((4500000000000000000000000 / 2) * 10000) / 9950);
  }

  function test_clampedExpansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 10_000_000e18); // EUR.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(500_000e18, false);

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);

    // amountGivenToPool: 450000000000000000000000
    // debt = 3_000_000e18 + 450000000000000000000000
    // coll = 10_000_000e18 - 450000000000000000000000 / 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 450000000000000000000000);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256((450000000000000000000000 / 2) * 10000) / 9950);
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_expansionIntegrationTest(uint256 fpmmDebt, uint256 fpmmColl, uint256 spDebt) public {
    fpmmDebt = bound(fpmmDebt, 3000e18, 100_000_000e18);
    fpmmColl = bound(fpmmColl, (fpmmDebt * 25) / 10, 1_000_000_000e18);

    _mintCDPCollToken(reserveMultisig, fpmmColl); // USD.m

    _openDemoTroves(fpmmDebt, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10); // eur.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, fpmmDebt, fpmmColl);
    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);

    // bound spDebt to be at least 1% of fpmmColl and at most the total fpmm collateral reserve
    spDebt = bound(spDebt, $liquity.stabilityPool.MIN_BOLD_AFTER_REBALANCE() + (fpmmColl * 5) / 100, fpmmColl);

    _mintCDPDebtToken(reserveMultisig, spDebt); // EUR.m
    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(spDebt, false);

    uint256 spDebtBalanceBefore = $tokens.cdpDebtToken.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceBefore = $tokens.cdpCollToken.balanceOf(address($liquity.stabilityPool));

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    uint256 spDebtBalanceAfter = $tokens.cdpDebtToken.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceAfter = $tokens.cdpCollToken.balanceOf(address($liquity.stabilityPool));

    assertGt(spCollBalanceAfter, spCollBalanceBefore, "SP should have more coll token");
    assertLt(spDebtBalanceAfter, spDebtBalanceBefore, "SP should have less debt token");

    uint256 minDebtLeftInSPPercentage = (spDebt * 9000) / 10000; // spool percentage is 90%
    uint256 minDebtLeftInSPHardFloor = $liquity.stabilityPool.MIN_BOLD_AFTER_REBALANCE();

    if (spDebtBalanceAfter > minDebtLeftInSPPercentage && spDebtBalanceAfter > minDebtLeftInSPHardFloor) {
      assertEq(pricesAfter.priceDifference, 0, "Expansion should be perfect, if we have more debt left in the SP");
    } else {
      assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Expansion should reduce price difference");
    }

    bool isDebtToken0 = $fpmm.fpmmCDP.token0() == address($tokens.cdpDebtToken);
    if (isDebtToken0) {
      assertGt(
        pricesAfter.reservePriceDenominator,
        pricesBefore.reservePriceDenominator,
        "There should be more of asset0 (debt)"
      );
      assertLt(
        pricesAfter.reservePriceNumerator,
        pricesBefore.reservePriceNumerator,
        "There should be less of asset1 (coll)"
      );
      assertEq(
        pricesAfter.reservePriceDenominator - pricesBefore.reservePriceDenominator,
        spDebtBalanceBefore - spDebtBalanceAfter,
        "Debt should move from SP to Pool"
      );
    } else {
      assertLt(
        pricesAfter.reservePriceDenominator,
        pricesBefore.reservePriceDenominator,
        "There should be less of asset0 (coll)"
      );
      assertGt(
        pricesAfter.reservePriceNumerator,
        pricesBefore.reservePriceNumerator,
        "There should be more of asset1 (debt)"
      );
      assertEq(
        pricesAfter.reservePriceNumerator - pricesBefore.reservePriceNumerator,
        spDebtBalanceBefore - spDebtBalanceAfter,
        "Debt should move from SP to Pool"
      );
    }
  }

  function test_targetContraction() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _openDemoTroves(11_000_000e18, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10);

    // price is 10:3 below oracle price
    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 10_000_000e18, 3_000_000e18);

    FPMMPrices memory pricesBeforeRebalance = _snapshotPrices($fpmm.fpmmCDP);

    // Debt amount to redeem :=  (ON*RD - OD*RN)/(ON*(2-i)) = 2005012531328320802005012
    uint256 expectedDebtToRedeem = 2005012531328320802005012;

    uint256 expectedCollInflow;
    if ($fpmm.fpmmCDP.token0() == address($tokens.cdpDebtToken)) {
      expectedCollInflow =
        (expectedDebtToRedeem * (1e18 - 0.005e18) * pricesBeforeRebalance.oraclePriceNumerator) /
        (pricesBeforeRebalance.oraclePriceDenominator * 1e18);
    } else {
      expectedCollInflow =
        (expectedDebtToRedeem * (1e18 - 0.005e18) * pricesBeforeRebalance.oraclePriceDenominator) /
        (pricesBeforeRebalance.oraclePriceNumerator * 1e18);
    }

    uint256 targetSupply = (expectedDebtToRedeem * 1e18) / (0.0025e18);
    _mintCDPDebtToken(makeAddr("alice"), targetSupply - $tokens.cdpDebtToken.totalSupply());

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfterRebalance = _snapshotPrices($fpmm.fpmmCDP);
    // base rate has decayed to min 0.25% so the amount redeemed is equal to 0.25% of the total supply.
    // in order for the total redemption fee to be equal to the incentive( 0.50%)

    uint256 reserveDebtOutflow;
    uint256 reserveCollInflow;
    if ($fpmm.fpmmCDP.token0() == address($tokens.cdpDebtToken)) {
      reserveDebtOutflow = pricesBeforeRebalance.reservePriceDenominator - pricesAfterRebalance.reservePriceDenominator;
      reserveCollInflow = pricesAfterRebalance.reservePriceNumerator - pricesBeforeRebalance.reservePriceNumerator;
    } else {
      reserveDebtOutflow = pricesBeforeRebalance.reservePriceNumerator - pricesAfterRebalance.reservePriceNumerator;
      reserveCollInflow = pricesAfterRebalance.reservePriceDenominator - pricesBeforeRebalance.reservePriceDenominator;
    }

    assertEq(pricesAfterRebalance.priceDifference, 0);
    assertEq(reserveDebtOutflow, expectedDebtToRedeem);
    assertEq(reserveCollInflow, expectedCollInflow);
  }

  function test_clampedContraction() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _openDemoTroves(11_000_000e18, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10);

    // price is 10:3 below oracle price
    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 10_000_000e18, 3_000_000e18);

    FPMMPrices memory pricesBeforeRebalance = _snapshotPrices($fpmm.fpmmCDP);

    uint256 expectedDebtToRedeem = ($tokens.cdpDebtToken.totalSupply() * 25) / 10_000;

    uint256 expectedRedemptionFee = $collateralRegistry.getRedemptionRateForRedeemedAmount(expectedDebtToRedeem);

    uint256 expectedCollInflow;
    if ($fpmm.fpmmCDP.token0() == address($tokens.cdpDebtToken)) {
      expectedCollInflow =
        (expectedDebtToRedeem * (1e18 - expectedRedemptionFee) * pricesBeforeRebalance.oraclePriceNumerator) /
        (pricesBeforeRebalance.oraclePriceDenominator * 1e18);
    } else {
      expectedCollInflow =
        (expectedDebtToRedeem * (1e18 - expectedRedemptionFee) * pricesBeforeRebalance.oraclePriceDenominator) /
        (pricesBeforeRebalance.oraclePriceNumerator * 1e18);
    }

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfterRebalance = _snapshotPrices($fpmm.fpmmCDP);

    // base rate has decayed to min 0.25% so the amount redeemed is equal to 0.25% of the total supply.
    // in order for the total redemption fee to be equal to the incentive( 0.50%)
    uint256 reserveDebtOutflow;
    uint256 reserveCollInflow;
    if ($fpmm.fpmmCDP.token0() == address($tokens.cdpDebtToken)) {
      reserveDebtOutflow = pricesBeforeRebalance.reservePriceDenominator - pricesAfterRebalance.reservePriceDenominator;
      reserveCollInflow = pricesAfterRebalance.reservePriceNumerator - pricesBeforeRebalance.reservePriceNumerator;
    } else {
      reserveDebtOutflow = pricesBeforeRebalance.reservePriceNumerator - pricesAfterRebalance.reservePriceNumerator;
      reserveCollInflow = pricesAfterRebalance.reservePriceDenominator - pricesBeforeRebalance.reservePriceDenominator;
    }

    assertEq(reserveDebtOutflow, expectedDebtToRedeem);
    // allow for 1 wei difference due to rounding errors from calculating expected collateral inflow:
    //  based on debt to redeem vs iterating over touched troves and calculating collateral received from each trove.
    assertApproxEqAbs(reserveCollInflow, expectedCollInflow, 1);
    assertLt(pricesAfterRebalance.priceDifference, pricesBeforeRebalance.priceDifference);
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_contractionIntegrationTest(uint256 fpmmDebt, uint256 fpmmColl, uint256 targetSupply) public {
    fpmmColl = bound(fpmmColl, 300e18, 100_000_000e18);
    fpmmDebt = bound(fpmmDebt, (fpmmColl * 25) / 10, 1_000_000_000e18);

    _mintCDPCollToken(reserveMultisig, fpmmColl); // USD.m

    _openDemoTroves(fpmmDebt, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10); // eur.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, fpmmDebt, fpmmColl);
    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);

    // bound targetSupply to allow for at least 20% of debt reserve to be redeemed
    uint256 supplyLowerBound = (((fpmmDebt * 20) / 100) * 1e18) /
      (50 * 1e14 - $collateralRegistry.getRedemptionRateWithDecay());
    uint256 supplyUpperBound = (((fpmmDebt * 80) / 100) * 1e18) /
      (50 * 1e14 - $collateralRegistry.getRedemptionRateWithDecay());
    targetSupply = bound(targetSupply, supplyLowerBound, supplyUpperBound);

    _mintCDPDebtToken(reserveMultisig, targetSupply - $tokens.cdpDebtToken.totalSupply());

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);

    assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference);

    if ($fpmm.fpmmCDP.token0() == address($tokens.cdpDebtToken)) {
      assertLt(
        pricesAfter.reservePriceDenominator,
        pricesBefore.reservePriceDenominator,
        "There should be less of asset0 (debt)"
      );
      assertGt(
        pricesAfter.reservePriceNumerator,
        pricesBefore.reservePriceNumerator,
        "There should be more of asset1 (coll)"
      );
    } else {
      assertLt(
        pricesAfter.reservePriceNumerator,
        pricesBefore.reservePriceNumerator,
        "There should be less of asset1 (debt)"
      );
      assertGt(
        pricesAfter.reservePriceDenominator,
        pricesBefore.reservePriceDenominator,
        "There should be more of asset0 (coll)"
      );
    }
  }
}

contract CDPFPMM_Token0Debt_Test is CDPFPMM_BaseTest {
  function setUp() public {
    _deployTokens({ isCollateralTokenToken0: false, isDebtTokenToken0: true });
    _deployOracleAdapter();
    _deployLiquidityStrategies();
    _deployFPMM({ invertCDPFPMMRate: true, invertReserveFPMMRate: false });
    _deployLiquity();
    _configureCDPLiquidityStrategy({
      cooldown: 60,
      incentiveBps: 50,
      stabilityPoolPercentage: 9000, // 90%
      maxIterations: 100
    });
    _configureReserveLiquidityStrategy({ cooldown: 0, incentiveBps: 50 });
    // skip 20 days to allow the base rate to decay
    skip(20 days);
    _checkSetup();
  }

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.cdpDebtToken), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.cdpCollToken), "CDPFPMM token1 mismatch");
  }
}

contract CDPFPMM_Token1Debt_Test is CDPFPMM_BaseTest {
  function setUp() public {
    _deployTokens({ isCollateralTokenToken0: false, isDebtTokenToken0: false });
    _deployOracleAdapter();
    _deployLiquidityStrategies();
    _deployFPMM({ invertCDPFPMMRate: false, invertReserveFPMMRate: false });
    _deployLiquity();
    _configureCDPLiquidityStrategy({
      cooldown: 60,
      incentiveBps: 50,
      stabilityPoolPercentage: 9000, // 90%
      maxIterations: 100
    });
    _configureReserveLiquidityStrategy({ cooldown: 0, incentiveBps: 50 });
    // skip 20 days to allow the base rate to decay
    skip(20 days);
    _checkSetup();
  }

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.cdpCollToken), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.cdpDebtToken), "CDPFPMM token1 mismatch");
  }
}
