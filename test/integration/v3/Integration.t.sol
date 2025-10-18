// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";

contract IntegrationTest is
  TokenDeployer,
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

    _deployOracleAdapter();

    _deployLiquidityStrategies();

    _deployFPMM({ invertCDPFPMMRate: false, invertReserveFPMMRate: false });

    _deployLiquity();

    _configureCDPLiquidityStrategy({
      cooldown: 60,
      incentiveBps: 50,
      stabilityPoolPercentage: 900, // 90%
      maxIterations: 100
    });
    _configureReserveLiquidityStrategy({ cooldown: 0, incentiveBps: 50 });

    _checkSetup();
  }

  function _checkSetup() private {
    assertEq($fpmm.fpmmCDP.token0(), address($tokens.debtToken), "CDPFPMM token0 mismatch");
    assertEq($fpmm.fpmmCDP.token1(), address($tokens.collateralToken), "CDPFPMM token1 mismatch");

    assertEq($fpmm.fpmmReserve.token0(), address($tokens.reserveCollateralToken), "ReserveFPMM token0 mismatch");
    assertEq($fpmm.fpmmReserve.token1(), address($tokens.collateralToken), "ReserveFPMM token1 mismatch");
  }
}
