// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";

contract FPMMTest is TokenDeployer, OracleAdapterDeployer, LiquidityStrategyDeployer, FPMMDeployer {
  function test_integrationV3_fpmmTest() public {
    _deployTokens(false, false);
    _deployOracleAdapter();
    _deployLiquidityStrategies();
    _deployFPMM(false, false);
  }
}
