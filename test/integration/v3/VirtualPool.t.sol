// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";
import { VirtualPoolDeployer } from "test/integration/v3/VirtualPoolDeployer.sol";

contract VirtualPoolTest is
  TokenDeployer,
  MentoV2Deployer,
  VirtualPoolDeployer,
  OracleAdapterDeployer,
  LiquidityStrategyDeployer,
  FPMMDeployer
{
  function setUp() public {
    _deployTokens(false, false);
    _deployMentoV2();
    _deployOracleAdapter();
    _deployLiquidityStrategies();
    _deployFPMM(false, false);
    _deployVirtualPools();
  }

  function test_virtualPools_dummy() public {
    assertTrue(true);
  }
}
