// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";

contract IntegrationTest is
  TokenDeployer,
  MentoV2Deployer,
  OracleAdapterDeployer,
  LiquidityStrategyDeployer,
  FPMMDeployer,
  LiquityDeployer
{
  address reserveMultisig = makeAddr("reserveMultisig");

  function setUp() public {
    // ReserveFPMM:  token0 = USDC, token1 = USD.m
    // CDPFPMM:      token0 = EUR.m, token1 = USD.m
    _deployTokens({ isCollateralTokenToken0: false, isDebtTokenToken0: true });

    _deployMentoV2();

    _deployOracleAdapter();

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

  function _checkSetup() private {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.eurm), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.usdm), "CDPFPMM token1 mismatch");

    assertEq($fpmm.fpmmReserve.token0(), address($tokens.usdc), "ReserveFPMM token0 mismatch");
    assertEq($fpmm.fpmmReserve.token1(), address($tokens.usdm), "ReserveFPMM token1 mismatch");
  }
}
