// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { CDPLiquidityStrategy } from "contracts/liquidityStrategies/CDPLiquidityStrategy.sol";
import { ReserveLiquidityStrategy } from "contracts/liquidityStrategies/ReserveLiquidityStrategy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
// solhint-disable-next-line max-line-length
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";

/**
 * @title LiquidityStrategyUpgradeabilityTest
 * @notice Tests for upgradeability of liquidity strategies using ProxyAdmin
 */
contract LiquidityStrategyUpgradeabilityTest is
  Test,
  LiquidityStrategyDeployer,
  TokenDeployer,
  MentoV2Deployer,
  OracleAdapterDeployer
{
  function setUp() public {
    _deployTokens(false, false);
    _deployOracleAdapter();
    _deployMentoV2();
    _deployLiquidityStrategies();
  }

  /**
   * @notice Test that ProxyAdmin is deployed and owned by governance
   */
  function test_proxyAdmin_shouldBeDeployedAndOwnedByGovernance() public view {
    ProxyAdmin proxyAdmin = _getProxyAdmin();
    assertNotEq(address(proxyAdmin), address(0), "ProxyAdmin should be deployed");
    assertEq(proxyAdmin.owner(), $addresses.governance, "ProxyAdmin should be owned by governance");
  }

  /**
   * @notice Test that CDPLiquidityStrategy can be upgraded
   */
  function test_cdpLiquidityStrategy_shouldBeUpgradeable() public {
    address oldImplementation = _getCDPLiquidityStrategyImplementation();
    assertNotEq(oldImplementation, address(0), "Current implementation should exist");

    CDPLiquidityStrategy newImplementation = new CDPLiquidityStrategy(true);
    assertNotEq(address(newImplementation), oldImplementation, "New implementation should be different from old");

    _upgradeCDPLiquidityStrategy(address(newImplementation));

    address currentImplementation = _getCDPLiquidityStrategyImplementation();
    assertEq(currentImplementation, address(newImplementation), "Implementation should be updated after upgrade");

    // Verify proxy still works and state is preserved
    assertEq(
      CDPLiquidityStrategy(address($liquidityStrategies.cdpLiquidityStrategy)).owner(),
      $addresses.governance,
      "Owner should be preserved after upgrade"
    );
  }

  /**
   * @notice Test that ReserveLiquidityStrategy can be upgraded
   */
  function test_reserveLiquidityStrategy_shouldBeUpgradeable() public {
    address oldImplementation = _getReserveLiquidityStrategyImplementation();
    assertNotEq(oldImplementation, address(0), "Current implementation should exist");

    ReserveLiquidityStrategy newImplementation = new ReserveLiquidityStrategy(true);
    assertNotEq(address(newImplementation), oldImplementation, "New implementation should be different from old");

    _upgradeReserveLiquidityStrategy(address(newImplementation));

    address currentImplementation = _getReserveLiquidityStrategyImplementation();
    assertEq(currentImplementation, address(newImplementation), "Implementation should be updated after upgrade");

    // Verify proxy still works and state is preserved
    assertEq(
      ReserveLiquidityStrategy(address($liquidityStrategies.reserveLiquidityStrategy)).owner(),
      $addresses.governance,
      "Owner should be preserved after upgrade"
    );
    assertEq(
      address(ReserveLiquidityStrategy(address($liquidityStrategies.reserveLiquidityStrategy)).reserve()),
      address($liquidityStrategies.reserveV2),
      "Reserve address should be preserved after upgrade"
    );
  }

  /**
   * @notice Test that only governance can upgrade through ProxyAdmin
   */
  function test_upgrade_whenCalledByNonGovernance_shouldRevert() public {
    CDPLiquidityStrategy newImplementation = new CDPLiquidityStrategy(true);

    address attacker = makeAddr("attacker");
    vm.prank(attacker);
    vm.expectRevert("Ownable: caller is not the owner");
    $liquidityStrategies.proxyAdmin.upgrade(
      ITransparentUpgradeableProxy(address($liquidityStrategies.cdpLiquidityStrategy)),
      address(newImplementation)
    );
  }
}
