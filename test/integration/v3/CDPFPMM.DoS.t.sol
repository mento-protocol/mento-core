// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";

contract CDPFPMM_Test_SP_REBALANCE_FRONTRUN is
  TokenDeployer,
  MentoV2Deployer,
  OracleAdapterDeployer,
  LiquidityStrategyDeployer,
  FPMMDeployer,
  LiquityDeployer
{
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
      liquiditySourceIncentiveContraction: 0.0025e18,
      protocolIncentiveContraction: 0.002506265664160401e18,
      liquiditySourceIncentiveExpansion: 0.0025e18,
      protocolIncentiveExpansion: 0.002506265664160401e18
    });
    _configureReserveLiquidityStrategy({
      cooldown: 0,
      liquiditySourceIncentiveContraction: 0.002506265664160401e18,
      protocolIncentiveContraction: 0.0025e18,
      liquiditySourceIncentiveExpansion: 0.002506265664160401e18,
      protocolIncentiveExpansion: 0.0025e18
    });
    // skip 20 days to allow the base rate to decay
    skip(20 days);
    _refreshOracleRates();
    _checkSetup();
  }

  function _checkSetup() internal {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.usdm), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.eurm), "CDPFPMM token1 mismatch");
  }

  function test_rebalance_fails_with_frontrun() public {
    // --- Setup system balances & initial pool liquidity ---
    address user = makeAddr("user");
    _mintCDPCollToken(user, 2e31);
    _mintCDPDebtToken(user, 2e31);
    address attacker = makeAddr("attacker");
    _mintCDPCollToken(attacker, 2e31);
    _mintCDPDebtToken(attacker, 2e31);

    vm.prank(user);
    $liquity.stabilityPool.provideToSP(1e30, false);

    // seed the FPMM with initial liquidity (pool roughly 1:2)
    _provideLiquidityToFPMM($fpmm.fpmmCDP, user, 10_000e23, 5_000e23);

    // --- User performs a large swap to heavily imbalance the pool ---
    vm.startPrank(user);
    $tokens.usdm.transfer(address($fpmm.fpmmCDP), 5_200e23);
    $fpmm.fpmmCDP.swap(0, 10_000e23 - 1, user, "");
    vm.stopPrank();
    // REBALANCE WILL ATTEMPT TO TRANSFER EUR.M, AND TAKE OUT USD.M
    // ATTACKER CAN FRONTRUN WITH A 1 WEI USD.M TRANSFER TO DOS THE REBALANCE
    vm.prank(attacker);

    $tokens.usdm.transfer(address($fpmm.fpmmCDP), 1);
    vm.prank(user);
    $liquidityStrategies.cdpLiquidityStrategy.rebalance(address($fpmm.fpmmCDP));
  }
}
