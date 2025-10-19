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
}
