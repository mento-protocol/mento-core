// SPDX-License-Identifier: MIT
// solhint-disable max-line-length
pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";

abstract contract CDPFPMM_BaseTest is
  TokenDeployer,
  MentoV2Deployer,
  OracleAdapterDeployer,
  LiquidityStrategyDeployer,
  FPMMDeployer,
  LiquityDeployer
{
  address reserveMultisig = makeAddr("reserveMultisig");
}

contract CDPFPMM_Token0Debt_Test is CDPFPMM_BaseTest {
  function setUp() public {
    _deployTokens({ isCollateralTokenToken0: false, isDebtTokenToken0: true });
    _deployOracleAdapter();
    _deployMentoV2();
    _deployLiquidityStrategies();
    _deployFPMM({ invertCDPFPMMRate: true, invertReserveFPMMRate: false });
    _deployLiquity();
    _configureCDPLiquidityStrategy({
      cooldown: 60,
      stabilityPoolPercentage: 9000, // 90%
      maxIterations: 100,
      liquiditySourceIncentiveBpsContraction: 25,
      protocolIncentiveBpsContraction: 25,
      liquiditySourceIncentiveBpsExpansion: 25,
      protocolIncentiveBpsExpansion: 25
    });
    _configureReserveLiquidityStrategy({
      cooldown: 0,
      liquiditySourceIncentiveBpsContraction: 25,
      protocolIncentiveBpsContraction: 25,
      liquiditySourceIncentiveBpsExpansion: 25,
      protocolIncentiveBpsExpansion: 25
    });
    // skip 20 days to allow the base rate to decay
    skip(20 days);
    _refreshOracleRates();
    _checkSetup();
  }

  function test_expansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 15_000_000e18); // EUR.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(10_000_000e18, false);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be above oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);
    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Expansion should always rebalance perfectly towards the threshold");

    // amountTakenFromPool: 4120308106125443208216163
    // debt = 3_000_000e18 + 4120308106125443208216163 * 2 * 9950 / 10000
    // coll = 10_000_000e18 - 4120308106125443208216163
    assertEq(fpmmCollAfter, 10_000_000e18 - 4120308106125443208216163);
    assertEq(fpmmDebtAfter, 3_000_000e18 + uint256(4120308106125443208216163 * 2 * 9950) / 10000);
  }

  function test_clampedExpansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 10_000_000e18); // EUR.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(500_000e18, false);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be above oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);
    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertGt(
      pricesAfter.priceDifference,
      500,
      "Price difference should be more then then threshold away from oracle price due to clamping"
    );

    // amountGivenToPool: 450000000000000000000000 (clamped)
    // debt = 3_000_000e18 + 450000000000000000000000
    // coll = 10_000_000e18 - 450000000000000000000000 / 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 450000000000000000000000);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256((450000000000000000000000 / 2) * 10000) / 9950);
  }

  function testFuzz_expansionIntegrationTest(uint256 fpmmDebt, uint256 fpmmColl, uint256 spDebt) public {
    fpmmDebt = bound(fpmmDebt, 3000e18, 100_000_000e18);
    fpmmColl = bound(fpmmColl, (fpmmDebt * 25) / 10, 1_000_000_000e18);

    _mintCDPCollToken(reserveMultisig, fpmmColl); // USD.m

    _openDemoTroves(fpmmDebt, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10); // eur.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, fpmmDebt, fpmmColl);
    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);

    assertTrue(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be above oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    // bound spDebt to be at least 1% of fpmmColl and at most the total fpmm collateral reserve
    spDebt = bound(spDebt, $liquity.systemParams.MIN_BOLD_AFTER_REBALANCE() + (fpmmColl * 5) / 100, fpmmColl);

    _mintCDPDebtToken(reserveMultisig, spDebt); // EUR.m
    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(spDebt, false);

    uint256 spDebtBalanceBefore = $tokens.eurm.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceBefore = $tokens.usdm.balanceOf(address($liquity.stabilityPool));

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Expansion should reduce price difference");

    uint256 spDebtBalanceAfter = $tokens.eurm.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceAfter = $tokens.usdm.balanceOf(address($liquity.stabilityPool));

    assertGt(spCollBalanceAfter, spCollBalanceBefore, "SP should have more coll token");
    assertLt(spDebtBalanceAfter, spDebtBalanceBefore, "SP should have less debt token");

    uint256 minDebtLeftInSPPercentage = (spDebt * 9000) / 10000; // spool percentage is 90%
    uint256 minDebtLeftInSPHardFloor = $liquity.systemParams.MIN_BOLD_AFTER_REBALANCE();

    if (spDebtBalanceAfter > minDebtLeftInSPPercentage && spDebtBalanceAfter > minDebtLeftInSPHardFloor) {
      assertEq(pricesAfter.priceDifference, 0, "Expansion should be perfect, if we have more debt left in the SP");
    } else {
      assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Expansion should reduce price difference");
    }

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
  }

  function test_targetContraction() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _openDemoTroves(11_000_000e18, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10);

    // price is 10:3 below oracle price
    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 10_000_000e18, 3_000_000e18);

    FPMMPrices memory pricesBeforeRebalance = _snapshotPrices($fpmm.fpmmCDP);

    uint256 expectedDebtToRedeem = 1799485861182519280205655;

    uint256 expectedCollInflow = uint256(
      expectedDebtToRedeem * (1e18 - 0.005e18) * pricesBeforeRebalance.oraclePriceNumerator
    ) / (pricesBeforeRebalance.oraclePriceDenominator * 1e18);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be below oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfterRebalance = _snapshotPrices($fpmm.fpmmCDP);

    uint256 reserveDebtOutflow = pricesBeforeRebalance.reservePriceDenominator -
      pricesAfterRebalance.reservePriceDenominator;
    uint256 reserveCollInflow = pricesAfterRebalance.reservePriceNumerator -
      pricesBeforeRebalance.reservePriceNumerator;

    assertApproxEqAbs(
      pricesAfterRebalance.priceDifference,
      500,
      1,
      "Price difference should be at the threshold with 1 Bps wiggle room due to rounding"
    );
    assertEq(reserveDebtOutflow, expectedDebtToRedeem);
    assertApproxEqAbs(
      reserveCollInflow,
      expectedCollInflow,
      1,
      "Coll inflow should be equal to the expected coll inflow with 1 wei difference due to rounding when hitting multiple troves"
    );
  }

  function testFuzz_contractionIntegrationTest(uint256 fpmmDebt, uint256 fpmmColl) public {
    fpmmColl = bound(fpmmColl, 300e18, 100_000_000e18);
    fpmmDebt = bound(fpmmDebt, (fpmmColl * 25) / 10, 1_000_000_000e18);

    _mintCDPCollToken(reserveMultisig, fpmmColl); // USD.m

    _openDemoTroves(fpmmDebt, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10); // eur.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be below oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still below oracle price");
    assertApproxEqAbs(
      pricesAfter.priceDifference,
      500,
      1,
      "Price difference should be at the threshold with 1 Bps wiggle room due to rounding"
    );

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
  }

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.eurm), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.usdm), "CDPFPMM token1 mismatch");
  }
}

contract CDPFPMM_Token1Debt_Test is CDPFPMM_BaseTest {
  function setUp() public {
    _deployTokens({ isCollateralTokenToken0: false, isDebtTokenToken0: false });
    _deployOracleAdapter();
    _deployMentoV2();
    _deployLiquidityStrategies();
    _deployFPMM({ invertCDPFPMMRate: false, invertReserveFPMMRate: false });
    _deployLiquity();
    _configureCDPLiquidityStrategy({
      cooldown: 60,
      stabilityPoolPercentage: 9000, // 90%
      maxIterations: 100,
      liquiditySourceIncentiveBpsContraction: 25,
      protocolIncentiveBpsContraction: 25,
      liquiditySourceIncentiveBpsExpansion: 25,
      protocolIncentiveBpsExpansion: 25
    });
    _configureReserveLiquidityStrategy({
      cooldown: 0,
      liquiditySourceIncentiveBpsContraction: 25,
      protocolIncentiveBpsContraction: 25,
      liquiditySourceIncentiveBpsExpansion: 25,
      protocolIncentiveBpsExpansion: 25
    });
    // skip 20 days to allow the base rate to decay
    skip(20 days);
    _refreshOracleRates();
    _checkSetup();
  }

  function test_expansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 15_000_000e18); // EUR.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(10_000_000e18, false);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be below oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);
    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still below oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Expansion should always rebalance perfectly towards the threshold");

    // amountTakenFromPool: 4113110539845758354755784
    // debt = 3_000_000e18 + 4113110539845758354755784 * 2 * 9950 / 10000
    // coll = 10_000_000e18 - 4113110539845758354755784
    assertEq(fpmmCollAfter, 10_000_000e18 - 4113110539845758354755784);
    assertEq(fpmmDebtAfter, 3_000_000e18 + uint256(4113110539845758354755784 * 2 * 9950) / 10000);
  }
  function test_clampedExpansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 10_000_000e18); // EUR.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(500_000e18, false);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be below oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);
    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still below oracle price");
    assertGt(
      pricesAfter.priceDifference,
      500,
      "Price difference should be more then then threshold away from oracle price due to clamping"
    );

    // amountGivenToPool: 450000000000000000000000 (clamped)
    // debt = 3_000_000e18 + 450000000000000000000000
    // coll = 10_000_000e18 - 450000000000000000000000 / 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 450000000000000000000000);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256((450000000000000000000000 / 2) * 10000) / 9950);
  }

  function testFuzz_expansionIntegrationTest(uint256 fpmmDebt, uint256 fpmmColl, uint256 spDebt) public {
    fpmmDebt = bound(fpmmDebt, 3000e18, 100_000_000e18);
    fpmmColl = bound(fpmmColl, (fpmmDebt * 25) / 10, 1_000_000_000e18);

    _mintCDPCollToken(reserveMultisig, fpmmColl); // USD.m

    _openDemoTroves(fpmmDebt, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10); // eur.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, fpmmDebt, fpmmColl);
    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);

    assertFalse(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be below oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    // bound spDebt to be at least 1% of fpmmColl and at most the total fpmm collateral reserve
    spDebt = bound(spDebt, $liquity.systemParams.MIN_BOLD_AFTER_REBALANCE() + (fpmmColl * 5) / 100, fpmmColl);

    _mintCDPDebtToken(reserveMultisig, spDebt); // EUR.m
    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(spDebt, false);

    uint256 spDebtBalanceBefore = $tokens.eurm.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceBefore = $tokens.usdm.balanceOf(address($liquity.stabilityPool));

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertFalse(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still below oracle price");
    assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Expansion should reduce price difference");

    uint256 spDebtBalanceAfter = $tokens.eurm.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceAfter = $tokens.usdm.balanceOf(address($liquity.stabilityPool));

    assertGt(spCollBalanceAfter, spCollBalanceBefore, "SP should have more coll token");
    assertLt(spDebtBalanceAfter, spDebtBalanceBefore, "SP should have less debt token");

    uint256 minDebtLeftInSPPercentage = (spDebt * 9000) / 10000; // spool percentage is 90%
    uint256 minDebtLeftInSPHardFloor = $liquity.systemParams.MIN_BOLD_AFTER_REBALANCE();

    if (spDebtBalanceAfter > minDebtLeftInSPPercentage && spDebtBalanceAfter > minDebtLeftInSPHardFloor) {
      assertEq(pricesAfter.priceDifference, 0, "Expansion should be perfect, if we have more debt left in the SP");
    } else {
      assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Expansion should reduce price difference");
    }

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

  function test_targetContraction() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _openDemoTroves(11_000_000e18, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10);

    // price is 10:3 below oracle price
    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 10_000_000e18, 3_000_000e18);

    FPMMPrices memory pricesBeforeRebalance = _snapshotPrices($fpmm.fpmmCDP);

    uint256 expectedDebtToRedeem = 1809512165301381586991074;

    uint256 expectedCollInflow = uint256(
      expectedDebtToRedeem * (1e18 - 0.005e18) * pricesBeforeRebalance.oraclePriceDenominator
    ) / (pricesBeforeRebalance.oraclePriceNumerator * 1e18);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be above oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfterRebalance = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesAfterRebalance.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertApproxEqAbs(
      pricesAfterRebalance.priceDifference,
      500,
      1,
      "Price difference should be at the threshold with 1 Bps wiggle room due to rounding"
    );

    uint256 reserveDebtOutflow = pricesBeforeRebalance.reservePriceNumerator -
      pricesAfterRebalance.reservePriceNumerator;
    uint256 reserveCollInflow = pricesAfterRebalance.reservePriceDenominator -
      pricesBeforeRebalance.reservePriceDenominator;

    assertApproxEqAbs(
      pricesAfterRebalance.priceDifference,
      500,
      1,
      "Price difference should be at the threshold with 1 Bps wiggle room due to rounding"
    );
    assertEq(reserveDebtOutflow, expectedDebtToRedeem);
    assertApproxEqAbs(
      reserveCollInflow,
      expectedCollInflow,
      1,
      "Coll inflow should be equal to the expected coll inflow with 1 wei difference due to rounding when hitting multiple troves"
    );
  }

  function testFuzz_contractionIntegrationTest(uint256 fpmmDebt, uint256 fpmmColl) public {
    fpmmColl = bound(fpmmColl, 300e18, 100_000_000e18);
    fpmmDebt = bound(fpmmDebt, (fpmmColl * 25) / 10, 1_000_000_000e18);

    _mintCDPCollToken(reserveMultisig, fpmmColl); // USD.m

    _openDemoTroves(fpmmDebt, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10); // eur.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be above oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    assertTrue(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertApproxEqAbs(
      pricesAfter.priceDifference,
      500,
      1,
      "Price difference should be at the threshold with 1 Bps wiggle room due to rounding"
    );

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

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.usdm), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.eurm), "CDPFPMM token1 mismatch");
  }
}
