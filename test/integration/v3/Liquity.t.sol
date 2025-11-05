// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";

contract Liquity is LiquityDeployer, OracleAdapterDeployer, MentoV2Deployer, LiquidityStrategyDeployer, TokenDeployer {
  function setUp() public {
    _deployTokens(false, false);
    _deployOracleAdapter();
    _deployMentoV2();
    _deployLiquidityStrategies();
  }

  function test_deployLiquity() public {
    _deployLiquity();

    uint256 trovesCount = $liquity.troveManager.getTroveIdsCount();
    assertEq(trovesCount, 0);

    address A = makeAddr("A");
    uint256 mintAmount = 10_000e18;

    assertEq($tokens.usdm.balanceOf(A), 0);

    vm.startPrank($addresses.governance);
    $tokens.usdm.setMinter(address(this), true);
    vm.stopPrank();

    $tokens.usdm.mint(A, mintAmount);
    assertEq($tokens.usdm.balanceOf(A), mintAmount);

    _openDemoTroves(200_000e18, $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(), 1e15, A, 50);

    assertEq($liquity.troveManager.getTroveIdsCount(), 50);
    assertEq($tokens.eurm.balanceOf(A), 200_000e18);
    assertEq(
      $tokens.usdm.balanceOf(address($liquityInternalPools.gasPool)),
      50 * $liquity.systemParams.ETH_GAS_COMPENSATION()
    );
  }
}
