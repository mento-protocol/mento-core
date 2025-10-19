// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { IntegrationTest } from "./Integration.t.sol";

contract CDPFPMM is IntegrationTest {
  function test_expansion() public {
    // Price is 2:1
    _mintCollateralToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintDebtToken(reserveMultisig, 10_000_000e18); // JPY.m

    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 3_000_000e18, 10_000_000e18);

    vm.prank(reserveMultisig);
    $liquity.stabilityPool.provideToSP(5_000_000e18, false);

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    // amountGivenToPool: 997493734335839598997493
    // reserve0 = 3_000_000e18 + 997493734335839598997493
    // reserve1 = 10_000_000e18 - 997493734335839598997493 * 2 * 9950 / 10_000
    assertEq($fpmm.fpmmCDP.reserve0(), 0);
    assertEq($fpmm.fpmmCDP.reserve1(), 0);
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
