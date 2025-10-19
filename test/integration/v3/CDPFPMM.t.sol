// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";

contract CDPFPMM is TokenDeployer, OracleAdapterDeployer, LiquidityStrategyDeployer, FPMMDeployer, LiquityDeployer {
  address reserveMultisig = makeAddr("reserveMultisig");

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
  }

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

  function test_clampedContraction() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _openDemoTroves(11_000_000e18, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10);

    // price is 10:3 below oracle price
    _provideLiquidityToFPMM($fpmm.fpmmCDP, reserveMultisig, 10_000_000e18, 3_000_000e18);

    FPMMPrices memory pricesBeforeRebalance = _snapshotPrices($fpmm.fpmmCDP);

    uint256 expectedDebtToRedeem = ($tokens.cdpDebtToken.totalSupply() * 25) / 10_000;

    uint256 expectedRedemptionFee = $collateralRegistry.getRedemptionRateForRedeemedAmount(expectedDebtToRedeem);

    uint256 expectedCollInflow = (expectedDebtToRedeem *
      (1e18 - expectedRedemptionFee) *
      pricesBeforeRebalance.oraclePriceNumerator) / (pricesBeforeRebalance.oraclePriceDenominator * 1e18);

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfterRebalance = _snapshotPrices($fpmm.fpmmCDP);

    // base rate has decayed to min 0.25% so the amount redeemed is equal to 0.25% of the total supply.
    // in order for the total redemption fee to be equal to the incentive( 0.50%)
    uint256 reserveDebtOutflow = pricesBeforeRebalance.reservePriceDenominator -
      pricesAfterRebalance.reservePriceDenominator;

    uint256 reserveCollInflow = pricesAfterRebalance.reservePriceNumerator -
      pricesBeforeRebalance.reservePriceNumerator;

    assertEq(reserveDebtOutflow, expectedDebtToRedeem);
    assertEq(reserveCollInflow, expectedCollInflow);
    assertLt(pricesAfterRebalance.priceDifference, pricesBeforeRebalance.priceDifference);
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

    uint256 expectedCollInflow = (expectedDebtToRedeem *
      (1e18 - 0.005e18) *
      pricesBeforeRebalance.oraclePriceNumerator) / (pricesBeforeRebalance.oraclePriceDenominator * 1e18);

    uint256 targetSupply = (expectedDebtToRedeem * 1e18) / (0.0025e18);

    // need better way to open troves in order to get to target supply
    // _openDemoTroves(
    //   targetSupply - $tokens.cdpDebtToken.totalSupply(),
    //   $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(),
    //   1e14,
    //   makeAddr("alice"),
    //   1
    // );

    _mintCDPDebtToken(makeAddr("alice"), targetSupply - $tokens.cdpDebtToken.totalSupply());

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));

    FPMMPrices memory pricesAfterRebalance = _snapshotPrices($fpmm.fpmmCDP);
    // base rate has decayed to min 0.25% so the amount redeemed is equal to 0.25% of the total supply.
    // in order for the total redemption fee to be equal to the incentive( 0.50%)
    uint256 reserveDebtOutflow = pricesBeforeRebalance.reservePriceDenominator -
      pricesAfterRebalance.reservePriceDenominator;

    uint256 reserveCollInflow = pricesAfterRebalance.reservePriceNumerator -
      pricesBeforeRebalance.reservePriceNumerator;

    assertEq(pricesAfterRebalance.priceDifference, 0);
    assertEq(reserveDebtOutflow, expectedDebtToRedeem);
    assertEq(reserveCollInflow, expectedCollInflow);
  }
}
