// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { console } from "forge-std/console.sol";
import { IntegrationTest } from "./Integration.t.sol";
import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";
import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";

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
    // amountGivenToPool: 997493734335839598997493
    // debt = 3_000_000e18 + 997493734335839598997493
    // coll = 10_000_000e18 - 997493734335839598997493 * 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 997493734335839598997493);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256(997493734335839598997493 * 2 * 10000) / 9950 - 1);
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
    // coll = 10_000_000e18 - 450000000000000000000000 * 2 * 9950 / 10_000
    assertEq(fpmmDebtAfter, 3_000_000e18 + 450000000000000000000000);
    assertEq(fpmmCollAfter, 10_000_000e18 - uint256(450000000000000000000000 * 2 * 10000) / 9950);
  }

  function test_contraction3() public {
    // Price is 2:1
    _mintCDPCollToken(reserveMultisig, 10_000_000e18); // USD.m
    _mintCDPDebtToken(reserveMultisig, 10_000_000e18); // EUR.m
    skip(10 days);
    _redeemCollateral(100, reserveMultisig);
    _openDemoTroves(10_000_000e18, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e14, reserveMultisig, 10);

    console.log("balance of cdp debt token", $tokens.cdpDebtToken.balanceOf(reserveMultisig));
    console.log("total supply of cdp debt token", $tokens.cdpDebtToken.totalSupply());
    console.log(
      "$tokens.cdpDebtToken.isBurner(address($collateralRegistry))",
      $tokens.cdpDebtToken.isBurner(address($collateralRegistry))
    );

    skip(10 days);
    // FPMMPrices memory pricesBeforeRedeem = _snapshotPrices($fpmm.fpmmCDP);
    _redeemCollateral(1, reserveMultisig);

    console.log("reserves after redeem");
    console.log("t0", $fpmm.fpmmCDP.reserve0());
    console.log("t1", $fpmm.fpmmCDP.reserve1());

    // skip(10 days);
    // _redeemCollateral(1, reserveMultisig);

    // skip(10 days);
    // _redeemCollateral(1, reserveMultisig);

    // skip(10 days);

    FPMMPrices memory pricesBefore = _snapshotPrices($fpmm.fpmmCDP);

    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));
  }
}
