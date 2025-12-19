// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";

abstract contract ReserveFPMM_BaseTest is
  TokenDeployer,
  OracleAdapterDeployer,
  MentoV2Deployer,
  LiquidityStrategyDeployer,
  FPMMDeployer,
  LiquityDeployer
{
  address reserveMultisig = makeAddr("reserveMultisig");
}

contract ReserveFPMM_Token1Debt_Test is ReserveFPMM_BaseTest {
  function setUp() public {
    // ReserveFPMM:  token0 = USDC, token1 = USD.m
    // CDPFPMM:      token0 = EUR.m, token1 = USD.m
    _deployTokens({ isCollateralTokenToken0: false, isDebtTokenToken0: true });

    _deployOracleAdapter();

    _deployMentoV2();

    _deployLiquidityStrategies();

    _deployFPMM({ invertCDPFPMMRate: false, invertReserveFPMMRate: false });

    _configureReserveLiquidityStrategy({
      cooldown: 0,
      liquiditySourceIncentiveBpsContraction: 25,
      protocolIncentiveBpsContraction: 25,
      liquiditySourceIncentiveBpsExpansion: 25,
      protocolIncentiveBpsExpansion: 25
    });

    _checkSetup();
  }

  function test_expansion() public {
    _mintResCollToken(reserveMultisig, 15_000_000e6);
    _mintResDebtToken(reserveMultisig, 15_000_000e18);
    uint256 fpmmDebt = 5_000_000e18;
    uint256 fpmmColl = 10_000_000e6;
    bool isDebtToken0 = $fpmm.fpmmReserve.token0() == address($tokens.usdm);
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);

    // amountTakenFromPool: 2313624678663
    // reserve0 = 10_000_000e6 - 2313624678663
    // reserve1 = 5_000_000e18 + ((2313624678663 * 9950) / 10_000) * 1e12
    uint256 fpmmDebtAfter = isDebtToken0 ? $fpmm.fpmmReserve.reserve0() : $fpmm.fpmmReserve.reserve1();
    uint256 fpmmCollAfter = isDebtToken0 ? $fpmm.fpmmReserve.reserve1() : $fpmm.fpmmReserve.reserve0();
    assertEq(fpmmCollAfter, 10_000_000e6 - 2313624678663);
    assertEq(fpmmDebtAfter, 5_000_000e18 + ((2313624678663 * 9950) / 10_000) * 1e12);
    assertEq(pricesAfter.priceDifference, 500, "Reserve price should be at the threshold away from oracle price");
    assertEq(pricesAfter.reservePriceAboveOraclePrice, false, "Reserve price should be still below oracle price");
  }

  function test_contraction() public {
    _mintResCollToken(address($liquidityStrategies.reserveV2), 10_000_000e6);
    _mintResCollToken(reserveMultisig, 10_000_000e6);
    _mintResDebtToken(reserveMultisig, 10_000_000e18);

    uint256 fpmmDebt = 10_000_000e18;
    uint256 fpmmColl = 5_000_000e6;
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);

    // amountTakenFromPool: 2323022374373395280596649
    // reserve0 = 5_000_000e6 + 2323022374373395280596649 * 9950 / 10000 / 1e12
    // reserve1 = 10_000_000e18 - 2323022374373395280596649
    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmReserve);
    assertEq(fpmmCollAfter, 5_000_000e6 + uint256(2323022374373395280596649 * 9950) / 1e16);
    assertEq(fpmmDebtAfter, 10_000_000e18 - 2323022374373395280596649);
    assertEq(pricesAfter.priceDifference, 500, "Reserve price should be at the threshold away from oracle price");
    assertEq(pricesAfter.reservePriceAboveOraclePrice, true, "Reserve price should be still above oracle price");
  }

  function test_clampedContraction() public {
    _mintResCollToken(address($liquidityStrategies.reserveV2), 1_000_000e6);
    _mintResCollToken(reserveMultisig, 10_000_000e6);
    _mintResDebtToken(reserveMultisig, 10_000_000e18);
    uint256 fpmmDebt = 10_000_000e18;
    uint256 fpmmColl = 5_000_000e6;
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);

    // amountGivenToPool: 1_000_000e6 (reserve0)
    // amountTakenFromPool: 1_000_000 * 1e18 * 10000 / 9950 = 1005025125628140703517587
    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmReserve);
    assertEq(fpmmCollAfter, 5_000_000e6 + 1_000_000e6);
    assertEq(fpmmDebtAfter, 10_000_000e18 - 1005025125628140703517587);
    assertGt(
      pricesAfter.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price due to clamping"
    );
    assertEq(pricesAfter.reservePriceAboveOraclePrice, true, "Reserve price should be still above oracle price");
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_expansion(uint256 fpmmDebt, uint256 fpmmColl) public {
    fpmmDebt = bound(fpmmDebt, 1e18, 100_000_000e18);
    fpmmColl = bound(fpmmColl, ((fpmmDebt / 1e12) * 3) / 2, 1_000_001_000e6);

    _mintResCollToken(reserveMultisig, fpmmColl);
    _mintResDebtToken(reserveMultisig, fpmmDebt);

    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceBefore = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyBefore = $tokens.usdm.totalSupply();

    assertFalse(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be below oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceAfter = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyAfter = $tokens.usdm.totalSupply();

    assertGt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have more collateral");
    assertFalse(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still below oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Expansion should always rebalance perfectly towards the threshold");

    assertGt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be minted");
    uint256 usdmTotalSupplyDelta = usdmTotalSupplyAfter - usdmTotalSupplyBefore;

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
      usdmTotalSupplyDelta,
      "Minted amount should equal reserve delta"
    );
    assertFalse(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still below oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Reserve price should be back to the threshold away from oracle price");
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_contraction(uint256 fpmmDebt, uint256 fpmmColl) public {
    fpmmColl = bound(fpmmColl, 1e6, 100_000_000e6);
    fpmmDebt = bound(fpmmDebt, ((fpmmColl * 1e12) * 3) / 2, 1_000_000_000e18);

    _mintResCollToken(reserveMultisig, fpmmColl);
    _mintResDebtToken(reserveMultisig, fpmmDebt);

    // Ensure there's enough collateral to rebalance the price
    _mintResCollToken(address($liquidityStrategies.reserveV2), fpmmDebt / 1e12);

    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceBefore = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyBefore = $tokens.usdm.totalSupply();
    assertTrue(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be above oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceAfter = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyAfter = $tokens.usdm.totalSupply();

    assertLt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have less collateral");
    if (reserveBalanceAfter > 0) {
      assertEq(
        pricesAfter.priceDifference,
        500,
        "Contraction should always rebalance perfectly towards the threshold, if enough collateral"
      );
    } else {
      assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Contraction should reduce price difference");
    }
    assertLt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be burned");
    uint256 usdmTotalSupplyDelta = usdmTotalSupplyBefore - usdmTotalSupplyAfter;

    assertGt(
      pricesAfter.reservePriceDenominator,
      pricesBefore.reservePriceDenominator,
      "There should be more of asset0 (coll)"
    );
    assertLt(
      pricesAfter.reservePriceNumerator,
      pricesBefore.reservePriceNumerator,
      "There should be less of asset1 (debt)"
    );
    assertApproxEqAbs(
      pricesBefore.reservePriceNumerator - pricesAfter.reservePriceNumerator,
      usdmTotalSupplyDelta + ((pricesBefore.reservePriceNumerator - pricesAfter.reservePriceNumerator) * 50) / 10000,
      1,
      "Burned amount should equal reserve delta minus the fees"
    );
    assertTrue(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Reserve price should be back to the threshold away from oracle price");
  }

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.eurm), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.usdm), "CDPFPMM token1 mismatch");

    assertEq($fpmm.fpmmReserve.token0(), address($tokens.usdc), "ReserveFPMM token0 mismatch");
    assertEq($fpmm.fpmmReserve.token1(), address($tokens.usdm), "ReserveFPMM token1 mismatch");
  }
}

contract ReserveFPMM_Token0Debt_Test is ReserveFPMM_BaseTest {
  function setUp() public {
    // ReserveFPMM:  token0 = USD.m, token1 = USDC
    // CDPFPMM:      token0 = EUR.m, token1 = USD.m
    _deployTokens({ isCollateralTokenToken0: true, isDebtTokenToken0: true });

    _deployOracleAdapter();

    _deployMentoV2();

    _deployLiquidityStrategies();

    _deployFPMM({ invertCDPFPMMRate: false, invertReserveFPMMRate: false });

    _configureReserveLiquidityStrategy({
      cooldown: 0,
      liquiditySourceIncentiveBpsContraction: 25,
      protocolIncentiveBpsContraction: 25,
      liquiditySourceIncentiveBpsExpansion: 25,
      protocolIncentiveBpsExpansion: 25
    });

    _checkSetup();
  }

  function test_expansion() public {
    _mintResCollToken(reserveMultisig, 15_000_000e6);
    _mintResDebtToken(reserveMultisig, 15_000_000e18);
    uint256 fpmmDebt = 5_000_000e18;
    uint256 fpmmColl = 10_000_000e6;
    bool isDebtToken0 = $fpmm.fpmmReserve.token0() == address($tokens.usdm);
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    (, , , , uint256 priceDifference, bool reservePriceAboveOraclePrice) = $fpmm.fpmmReserve.getPrices();

    // amountTakenFromPool: 2323022374373
    // reserve0 = 10_000_000e6 - 2323022374373
    // reserve1 = 5_000_000e18 + ((2323022374373 * 9950) / 10_000) * 1e12
    uint256 fpmmDebtAfter = isDebtToken0 ? $fpmm.fpmmReserve.reserve0() : $fpmm.fpmmReserve.reserve1();
    uint256 fpmmCollAfter = isDebtToken0 ? $fpmm.fpmmReserve.reserve1() : $fpmm.fpmmReserve.reserve0();
    assertEq(fpmmCollAfter, 10_000_000e6 - 2323022374373);
    assertEq(fpmmDebtAfter, 5_000_000e18 + ((2323022374373 * 9950) / 10_000) * 1e12);
    assertEq(priceDifference, 500, "Reserve price should be at the threshold away from oracle price");
    assertEq(reservePriceAboveOraclePrice, true, "Reserve price should be still above oracle price");
  }

  function test_contraction() public {
    _mintResCollToken(address($liquidityStrategies.reserveV2), 10_000_000e6);
    _mintResCollToken(reserveMultisig, 10_000_000e6);
    _mintResDebtToken(reserveMultisig, 10_000_000e18);

    uint256 fpmmDebt = 10_000_000e18;
    uint256 fpmmColl = 5_000_000e6;
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);

    // amountTakenFromPool: 2313624678663239074550128
    // reserve0 = 5_000_000e6 + 2313624678663239074550128 * 9950 / 10000 / 1e12
    // reserve1 = 10_000_000e18 - 2313624678663239074550128
    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmReserve);
    assertEq(fpmmCollAfter, 5_000_000e6 + uint256(2313624678663239074550128 * 9950) / 1e16);
    assertEq(fpmmDebtAfter, 10_000_000e18 - 2313624678663239074550128);
    assertEq(pricesAfter.priceDifference, 500, "Reserve price should be at the threshold away from oracle price");
    assertEq(pricesAfter.reservePriceAboveOraclePrice, false, "Reserve price should be still below oracle price");
  }

  function test_clampedContraction() public {
    _mintResCollToken(address($liquidityStrategies.reserveV2), 1_000_000e6);
    _mintResCollToken(reserveMultisig, 10_000_000e6);
    _mintResDebtToken(reserveMultisig, 10_000_000e18);
    uint256 fpmmDebt = 10_000_000e18;
    uint256 fpmmColl = 5_000_000e6;
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);

    // amountGivenToPool: 1_000_000e6 (reserve0)
    // amountTakenFromPool: 1_000_000 * 1e18 * 10000 / 9950 = 1005025125628140703517587
    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmReserve);
    assertEq(fpmmCollAfter, 5_000_000e6 + 1_000_000e6);
    assertEq(fpmmDebtAfter, 10_000_000e18 - 1005025125628140703517587);
    assertGt(
      pricesAfter.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price due to clamping"
    );
    assertEq(pricesAfter.reservePriceAboveOraclePrice, false, "Reserve price should be still below oracle price");
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_expansion(uint256 fpmmDebt, uint256 fpmmColl) public {
    fpmmDebt = bound(fpmmDebt, 1e18, 100_000_000e18);
    fpmmColl = bound(fpmmColl, ((fpmmDebt / 1e12) * 3) / 2, 1_000_001_000e6);

    _mintResCollToken(reserveMultisig, fpmmColl);
    _mintResDebtToken(reserveMultisig, fpmmDebt);

    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceBefore = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyBefore = $tokens.usdm.totalSupply();

    assertTrue(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be above oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceAfter = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyAfter = $tokens.usdm.totalSupply();

    assertGt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have more collateral");
    assertTrue(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Expansion should always rebalance perfectly towards the threshold");

    assertGt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be minted");
    uint256 usdmTotalSupplyDelta = usdmTotalSupplyAfter - usdmTotalSupplyBefore;

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
      usdmTotalSupplyDelta,
      "Minted amount should equal reserve delta"
    );
    assertTrue(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still above oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Reserve price should be back to the threshold away from oracle price");
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_contraction(uint256 fpmmDebt, uint256 fpmmColl) public {
    fpmmColl = bound(fpmmColl, 1e6, 100_000_000e6);
    fpmmDebt = bound(fpmmDebt, ((fpmmColl * 1e12) * 3) / 2, 1_000_000_000e18);

    _mintResCollToken(reserveMultisig, fpmmColl);
    _mintResDebtToken(reserveMultisig, fpmmDebt);

    // Ensure there's enough collateral to rebalance the price
    _mintResCollToken(address($liquidityStrategies.reserveV2), fpmmDebt / 1e12);

    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceBefore = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyBefore = $tokens.usdm.totalSupply();
    assertFalse(pricesBefore.reservePriceAboveOraclePrice, "Reserve price should be below oracle price");
    assertGt(
      pricesBefore.priceDifference,
      500,
      "Reserve price should be more then then threshold away from oracle price"
    );

    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceAfter = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyAfter = $tokens.usdm.totalSupply();

    assertLt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have less collateral");
    if (reserveBalanceAfter > 0) {
      assertEq(
        pricesAfter.priceDifference,
        500,
        "Contraction should always rebalance perfectly towards the threshold, if enough collateral"
      );
    } else {
      assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Contraction should reduce price difference");
    }
    assertLt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be burned");
    uint256 usdmTotalSupplyDelta = usdmTotalSupplyBefore - usdmTotalSupplyAfter;

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
    assertApproxEqAbs(
      pricesBefore.reservePriceDenominator - pricesAfter.reservePriceDenominator,
      usdmTotalSupplyDelta +
        ((pricesBefore.reservePriceDenominator - pricesAfter.reservePriceDenominator) * 50) /
        10000,
      1,
      "Burned amount should equal reserve delta minus the fees"
    );

    assertFalse(pricesAfter.reservePriceAboveOraclePrice, "Reserve price should be still below oracle price");
    assertEq(pricesAfter.priceDifference, 500, "Reserve price should be back to the threshold away from oracle price");
  }

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.eurm), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.usdm), "CDPFPMM token1 mismatch");

    assertEq($fpmm.fpmmReserve.token1(), address($tokens.usdc), "ReserveFPMM token1 mismatch");
    assertEq($fpmm.fpmmReserve.token0(), address($tokens.usdm), "ReserveFPMM token0 mismatch");
  }
}
