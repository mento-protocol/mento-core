// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { console } from "forge-std/console.sol";
import { IntegrationTest } from "./Integration.t.sol";

contract CDPFPMM is IntegrationTest {
  function test_expansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 10_000_000e18); // JPY.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(5_000_000e18, false);

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);
    // amountGivenToPool: 997493734335839598997493
    // debt = 3_000_000e18 + 997493734335839598997493
    // coll = 10_000_000e18 - 997493734335839598997493 * 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 997493734335839598997493);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256(997493734335839598997493 * 2 * 10000) / 9950 - 1);
  }

  function test_clampedExpansion() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 10_000_000e18); // JPY.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(500_000e18, false);

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmCDP);
    // amountGivenToPool: 450000000000000000000000
    // debt = 3_000_000e18 + 450000000000000000000000
    // coll = 10_000_000e18 - 450000000000000000000000 * 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 450000000000000000000000);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256(450000000000000000000000 * 2 * 10000) / 9950);
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_expansion(uint256 fpmmDebt, uint256 fpmmColl, uint256 spDebt) public {
    fpmmDebt = bound(fpmmDebt, 3000e18, 100_000_000e18);
    fpmmColl = bound(fpmmColl, (fpmmDebt * 3), 1_000_000_000e18);
    spDebt = bound(spDebt, fpmmDebt / 3, fpmmDebt);

    _mintCDPCollToken(reserveMultisig, fpmmColl); // USD.m
    _mintCDPDebtToken(reserveMultisig, fpmmDebt + spDebt); // EUR.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, fpmmDebt, fpmmColl);
    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(spDebt, false);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);
    uint256 spDebtBalanceBefore = $tokens.cdpDebtToken.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceBefore = $tokens.cdpCollToken.balanceOf(address($liquity.stabilityPool));

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmCDP);
    uint256 spDebtBalanceAfter = $tokens.cdpDebtToken.balanceOf(address($liquity.stabilityPool));
    uint256 spCollBalanceAfter = $tokens.cdpCollToken.balanceOf(address($liquity.stabilityPool));

    assertGt(spCollBalanceAfter, spCollBalanceBefore, "SP should have more coll token");
    assertLt(spDebtBalanceAfter, spDebtBalanceBefore, "SP should have less debt token");

    uint256 minDebtLeftInSP = (spDebt * 9000) / 10000; // spool percentage is 90%

    console.log(minDebtLeftInSP);
    if (spDebtBalanceAfter > minDebtLeftInSP) {
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

  // function test_contraction() public {
  //   _mintReserveCollateralToken(address($liquidityStrategies.reserve), 10_000_000e6);
  //   _mintReserveCollateralToken(reserveMultisig, 10_000_000e6);
  //   _mintCollateralToken(reserveMultisig, 10_000_000e18);

  //   _provideLiquidityToOneToOneFPMM(reserveMultisig, 5_000_000e6, 10_000_000e18);
  //   $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

  //   // amountTakenFromPool: 2506265664160401002506265
  //   // reserve0 = 5_000_000e6 + 2506265664160401002506265 * 9950 / 10000 / 1e12
  //   // reserve1 = 10_000_000e18 - 2506265664160401002506265
  //   assertEq($fpmm.fpmmReserve.reserve0(), 5_000_000e6 + uint256(2506265664160401002506265 * 9950) / 1e16);
  //   assertEq($fpmm.fpmmReserve.reserve1(), 10_000_000e18 - 2506265664160401002506265);
  // }

  // function test_clampedContraction() public {
  //   _mintReserveCollateralToken(address($liquidityStrategies.reserve), 1_000_000e6);
  //   _mintReserveCollateralToken(reserveMultisig, 10_000_000e6);
  //   _mintCollateralToken(reserveMultisig, 10_000_000e18);

  //   _provideLiquidityToOneToOneFPMM(reserveMultisig, 5_000_000e6, 10_000_000e18);
  //   $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

  //   // amountGivenToPool: 1_000_000e6 (reserve0)
  //   // amountTakenFromPool: 1_000_000 * 1e18 * 10000 / 9950 = 1005025125628140703517587
  //   assertEq($fpmm.fpmmReserve.reserve0(), 5_000_000e6 + 1_000_000e6);
  //   assertEq($fpmm.fpmmReserve.reserve1(), 10_000_000e18 - 1005025125628140703517587);
  // }

  // /// forge-config: default.fuzz.runs = 10000
  // function testFuzz_expansion(uint256 fpmmDebt, uint256 fpmmColl) public {
  //   fpmmDebt = bound(fpmmDebt, 1e18, 100_000_000e18);
  //   fpmmColl = bound(fpmmColl, ((fpmmDebt / 1e12) * 3) / 2, 1_000_001_000e6);

  //   _mintReserveCollateralToken(reserveMultisig, fpmmColl);
  //   _mintCollateralToken(reserveMultisig, fpmmDebt);

  //   bool isDebtToken0 = $fpmm.fpmmReserve.token0() == address($tokens.debtToken);
  //   if (isDebtToken0) {
  //     _provideLiquidityToOneToOneFPMM(reserveMultisig, fpmmDebt, fpmmColl);
  //   } else {
  //     _provideLiquidityToOneToOneFPMM(reserveMultisig, fpmmColl, fpmmDebt);
  //   }

  //   FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
  //   uint256 reserveBalanceBefore = $tokens.reserveCollateralToken.balanceOf(address($liquidityStrategies.reserve));
  //   uint256 usdmTotalSupplyBefore = $tokens.collateralToken.totalSupply();
  //   $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));
  //   FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
  //   uint256 reserveBalanceAfter = $tokens.reserveCollateralToken.balanceOf(address($liquidityStrategies.reserve));
  //   uint256 usdmTotalSupplyAfter = $tokens.collateralToken.totalSupply();

  //   assertGt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have more collateral");
  //   assertEq(pricesAfter.priceDifference, 0, "Expansion should always rebalance perfectly");

  //   assertGt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be minted");
  //   uint256 usdmTotalSupplyDelta = usdmTotalSupplyAfter - usdmTotalSupplyBefore;

  //   if (isDebtToken0) {
  //     assertGt(
  //       pricesAfter.reservePriceDenominator,
  //       pricesBefore.reservePriceDenominator,
  //       "There should be more of asset0 (debt)"
  //     );
  //     assertLt(
  //       pricesAfter.reservePriceNumerator,
  //       pricesBefore.reservePriceNumerator,
  //       "There should be less of asset1 (coll)"
  //     );
  //     assertEq(
  //       pricesAfter.reservePriceDenominator - pricesBefore.reservePriceDenominator,
  //       usdmTotalSupplyDelta,
  //       "Minted amount should equal reserve delta"
  //     );
  //   } else {
  //     assertLt(
  //       pricesAfter.reservePriceDenominator,
  //       pricesBefore.reservePriceDenominator,
  //       "There should be less of asset0 (coll)"
  //     );
  //     assertGt(
  //       pricesAfter.reservePriceNumerator,
  //       pricesBefore.reservePriceNumerator,
  //       "There should be more of asset1 (debt)"
  //     );
  //     assertEq(
  //       pricesAfter.reservePriceNumerator - pricesBefore.reservePriceNumerator,
  //       usdmTotalSupplyDelta,
  //       "Minted amount should equal reserve delta"
  //     );
  //   }
  // }

  // function testFuzz_contraction(uint256 fpmmDebt, uint256 fpmmColl, uint256 reserveColl) public {
  //   fpmmColl = bound(fpmmColl, 1e6, 100_000_000e6);
  //   fpmmDebt = bound(fpmmDebt, ((fpmmColl * 1e12) * 3) / 2, 1_000_000_000e18);
  //   // Ensure there's enough collateral to improve the price
  //   reserveColl = bound(reserveColl, (fpmmDebt * 1) / 3 / 1e12, fpmmDebt / 1e12);

  //   _mintReserveCollateralToken(reserveMultisig, fpmmColl);
  //   _mintCollateralToken(reserveMultisig, fpmmDebt);
  //   _mintReserveCollateralToken(address($liquidityStrategies.reserve), reserveColl);

  //   bool isDebtToken0 = $fpmm.fpmmReserve.token0() == address($tokens.debtToken);
  //   if (isDebtToken0) {
  //     _provideLiquidityToOneToOneFPMM(reserveMultisig, fpmmDebt, fpmmColl);
  //   } else {
  //     _provideLiquidityToOneToOneFPMM(reserveMultisig, fpmmColl, fpmmDebt);
  //   }

  //   FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
  //   uint256 reserveBalanceBefore = $tokens.reserveCollateralToken.balanceOf(address($liquidityStrategies.reserve));
  //   uint256 usdmTotalSupplyBefore = $tokens.collateralToken.totalSupply();
  //   $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));
  //   FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
  //   uint256 reserveBalanceAfter = $tokens.reserveCollateralToken.balanceOf(address($liquidityStrategies.reserve));
  //   uint256 usdmTotalSupplyAfter = $tokens.collateralToken.totalSupply();

  //   assertLt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have less collateral");
  //   if (reserveBalanceAfter > 0) {
  //     assertEq(pricesAfter.priceDifference, 0, "Contraction should always rebalance perfectly, if enough collateral");
  //   } else {
  //     assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Countration should reduce price difference");
  //   }
  //   assertLt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be burned");
  //   uint256 usdmTotalSupplyDelta = usdmTotalSupplyBefore - usdmTotalSupplyAfter;

  //   if (isDebtToken0) {
  //     assertLt(
  //       pricesAfter.reservePriceDenominator,
  //       pricesBefore.reservePriceDenominator,
  //       "There should be less of asset0 (debt)"
  //     );
  //     assertGt(
  //       pricesAfter.reservePriceNumerator,
  //       pricesBefore.reservePriceNumerator,
  //       "There should be more of asset1 (coll)"
  //     );
  //     assertEq(
  //       pricesBefore.reservePriceDenominator - pricesAfter.reservePriceDenominator,
  //       usdmTotalSupplyDelta,
  //       "Burned amount should equal reserve delta"
  //     );
  //   } else {
  //     assertGt(
  //       pricesAfter.reservePriceDenominator,
  //       pricesBefore.reservePriceDenominator,
  //       "There should be more of asset0 (coll)"
  //     );
  //     assertLt(
  //       pricesAfter.reservePriceNumerator,
  //       pricesBefore.reservePriceNumerator,
  //       "There should be less of asset1 (debt)"
  //     );
  //     assertEq(
  //       pricesBefore.reservePriceNumerator - pricesAfter.reservePriceNumerator,
  //       usdmTotalSupplyDelta,
  //       "Burned amount should equal reserve delta"
  //     );
  //   }
  // }
}
