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

  function test_expansion() public {
    _mintResCollToken(reserveMultisig, 10_000_000e6);
    _mintResDebtToken(reserveMultisig, 10_000_000e18);
    uint256 fpmmDebt = 5_000_000e18;
    uint256 fpmmColl = 10_000_000e6;
    bool isDebtToken0 = $fpmm.fpmmReserve.token0() == address($tokens.usdm);
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    // amountGivenToPool: 2506265664160
    // reserve0 = 10_000_000e6 - 2506265664160
    // reserve1 = 5_000_000e18 + ((2506265664160 * 9950) / 10_000) * 1e12
    uint256 fpmmDebtAfter = isDebtToken0 ? $fpmm.fpmmReserve.reserve0() : $fpmm.fpmmReserve.reserve1();
    uint256 fpmmCollAfter = isDebtToken0 ? $fpmm.fpmmReserve.reserve1() : $fpmm.fpmmReserve.reserve0();
    assertEq(fpmmCollAfter, 10_000_000e6 - 2506265664160);
    assertEq(fpmmDebtAfter, 5_000_000e18 + ((2506265664160 * 9950) / 10_000) * 1e12);
  }

  function test_contraction() public {
    _mintResCollToken(address($liquidityStrategies.reserveV2), 10_000_000e6);
    _mintResCollToken(reserveMultisig, 10_000_000e6);
    _mintResDebtToken(reserveMultisig, 10_000_000e18);

    uint256 fpmmDebt = 10_000_000e18;
    uint256 fpmmColl = 5_000_000e6;
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    // amountTakenFromPool: 2506265664160401002506265
    // reserve0 = 5_000_000e6 + 2506265664160401002506265 * 9950 / 10000 / 1e12
    // reserve1 = 10_000_000e18 - 2506265664160401002506265
    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmReserve);
    assertEq(fpmmCollAfter, 5_000_000e6 + uint256(2506265664160401002506265 * 9950) / 1e16);
    assertEq(fpmmDebtAfter, 10_000_000e18 - 2506265664160401002506265);
  }

  // reserveDebt (USDm)
  // reserveColl (USDC)

  // cdpColl (== reserveDebt, USDm)
  // cdpDebt (EURm)

  function test_clampedContraction() public {
    _mintResCollToken(address($liquidityStrategies.reserveV2), 1_000_000e6);
    _mintResCollToken(reserveMultisig, 10_000_000e6);
    _mintResDebtToken(reserveMultisig, 10_000_000e18);
    uint256 fpmmDebt = 10_000_000e18;
    uint256 fpmmColl = 5_000_000e6;
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));

    // amountGivenToPool: 1_000_000e6 (reserve0)
    // amountTakenFromPool: 1_000_000 * 1e18 * 10000 / 9950 = 1005025125628140703517587
    (uint256 fpmmDebtAfter, uint256 fpmmCollAfter) = _fpmmReserves($fpmm.fpmmReserve);
    assertEq(fpmmCollAfter, 5_000_000e6 + 1_000_000e6);
    assertEq(fpmmDebtAfter, 10_000_000e18 - 1005025125628140703517587);
  }

  /// forge-config: default.fuzz.runs = 10000
  function testFuzz_expansion(uint256 fpmmDebt, uint256 fpmmColl) public {
    fpmmDebt = bound(fpmmDebt, 1e18, 100_000_000e18);
    fpmmColl = bound(fpmmColl, ((fpmmDebt / 1e12) * 3) / 2, 1_000_001_000e6);

    _mintResCollToken(reserveMultisig, fpmmColl);
    _mintResDebtToken(reserveMultisig, fpmmDebt);

    bool isDebtToken0 = $fpmm.fpmmReserve.token0() == address($tokens.usdm);
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceBefore = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyBefore = $tokens.usdm.totalSupply();
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));
    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceAfter = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyAfter = $tokens.usdm.totalSupply();

    assertGt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have more collateral");
    assertEq(pricesAfter.priceDifference, 0, "Expansion should always rebalance perfectly");

    assertGt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be minted");
    uint256 usdmTotalSupplyDelta = usdmTotalSupplyAfter - usdmTotalSupplyBefore;

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
        usdmTotalSupplyDelta,
        "Minted amount should equal reserve delta"
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
        usdmTotalSupplyDelta,
        "Minted amount should equal reserve delta"
      );
    }
  }

  function testFuzz_contraction(uint256 fpmmDebt, uint256 fpmmColl, uint256 reserveColl) public {
    fpmmColl = bound(fpmmColl, 1e6, 100_000_000e6);
    fpmmDebt = bound(fpmmDebt, ((fpmmColl * 1e12) * 3) / 2, 1_000_000_000e18);
    // Ensure there's enough collateral to improve the price
    reserveColl = bound(reserveColl, (fpmmDebt * 1) / 3 / 1e12, fpmmDebt / 1e12);

    _mintResCollToken(reserveMultisig, fpmmColl);
    _mintResDebtToken(reserveMultisig, fpmmDebt);
    _mintResCollToken(address($liquidityStrategies.reserveV2), reserveColl);

    bool isDebtToken0 = $fpmm.fpmmReserve.token0() == address($tokens.usdm);
    _provideLiquidityToFPMM($fpmm.fpmmReserve, reserveMultisig, fpmmDebt, fpmmColl);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceBefore = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyBefore = $tokens.usdm.totalSupply();
    $liquidityStrategies.reserveLiquidityStrategy.rebalance(address($fpmm.fpmmReserve));
    FPMMPrices memory pricesAfter = _snapshotPrices($fpmm.fpmmReserve);
    uint256 reserveBalanceAfter = $tokens.usdc.balanceOf(address($liquidityStrategies.reserveV2));
    uint256 usdmTotalSupplyAfter = $tokens.usdm.totalSupply();

    assertLt(reserveBalanceAfter, reserveBalanceBefore, "Reserve should have less collateral");
    if (reserveBalanceAfter > 0) {
      assertEq(pricesAfter.priceDifference, 0, "Contraction should always rebalance perfectly, if enough collateral");
    } else {
      assertLt(pricesAfter.priceDifference, pricesBefore.priceDifference, "Countration should reduce price difference");
    }
    assertLt(usdmTotalSupplyAfter, usdmTotalSupplyBefore, "USD.m should be burned");
    uint256 usdmTotalSupplyDelta = usdmTotalSupplyBefore - usdmTotalSupplyAfter;

    if (isDebtToken0) {
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
      assertEq(
        pricesBefore.reservePriceDenominator - pricesAfter.reservePriceDenominator,
        usdmTotalSupplyDelta,
        "Burned amount should equal reserve delta"
      );
    } else {
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
      assertEq(
        pricesBefore.reservePriceNumerator - pricesAfter.reservePriceNumerator,
        usdmTotalSupplyDelta,
        "Burned amount should equal reserve delta"
      );
    }
  }
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

    _deployLiquity();

    _configureCDPLiquidityStrategy({
      cooldown: 60,
      incentiveBps: 50,
      stabilityPoolPercentage: 9000, // 90%
      maxIterations: 100,
      troveOwnerRedemptionFee: 25,
      protocolRedemptionFee: 25
    });
    _configureReserveLiquidityStrategy({ cooldown: 0, incentiveBps: 50 });

    _checkSetup();
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

    _deployLiquity();

    _configureCDPLiquidityStrategy({
      cooldown: 60,
      incentiveBps: 50,
      stabilityPoolPercentage: 9000, // 90%
      maxIterations: 100,
      troveOwnerRedemptionFee: 25,
      protocolRedemptionFee: 25
    });
    _configureReserveLiquidityStrategy({ cooldown: 0, incentiveBps: 50 });

    _checkSetup();
  }

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.eurm), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.usdm), "CDPFPMM token1 mismatch");

    assertEq($fpmm.fpmmReserve.token1(), address($tokens.usdc), "ReserveFPMM token1 mismatch");
    assertEq($fpmm.fpmmReserve.token0(), address($tokens.usdm), "ReserveFPMM token0 mismatch");
  }
}
