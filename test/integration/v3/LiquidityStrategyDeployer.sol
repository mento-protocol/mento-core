// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TestStorage } from "test/integration/v3/TestStorage.sol";
import { CDPLiquidityStrategy } from "contracts/liquidityStrategies/CDPLiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { ReserveLiquidityStrategy } from "contracts/liquidityStrategies/ReserveLiquidityStrategy.sol";
import { IReserveLiquidityStrategy } from "contracts/interfaces/IReserveLiquidityStrategy.sol";
import { ReserveV2 } from "contracts/swap/ReserveV2.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
// solhint-disable-next-line max-line-length
import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LiquidityStrategyDeployer is TestStorage {
  function _deployLiquidityStrategies() internal {
    _deployProxyAdmin();
    _deployCDPLiquidityStrategy();
    _deployReserveLiquidityStrategy();
    $liquidityStrategies.deployed = true;
    vm.label(address($liquidityStrategies.cdpLiquidityStrategy), "CDPLiquidityStrategy");
    vm.label(address($liquidityStrategies.reserveLiquidityStrategy), "ReserveLiquidityStrategy");
    vm.label(address($liquidityStrategies.reserve), "Reserve");
    vm.label(address($liquidityStrategies.proxyAdmin), "LiquidityStrategiesProxyAdmin");
  }

  function _deployProxyAdmin() private {
    // Deploy ProxyAdmin owned by governance
    ProxyAdmin proxyAdmin = new ProxyAdmin();
    proxyAdmin.transferOwnership($addresses.governance);
    $liquidityStrategies.proxyAdmin = proxyAdmin;
  }

  function _configureCDPLiquidityStrategy(
    uint64 cooldown,
    uint32 incentiveBps,
    uint256 stabilityPoolPercentage,
    uint256 maxIterations
  ) internal {
    require($liquidityStrategies.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: liquidity strategies not deployed");
    require($liquity.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: liquity not deployed");

    vm.startPrank($addresses.governance);
    $liquidityStrategies.cdpLiquidityStrategy.addPool(
      address($fpmm.fpmmCDP),
      address($tokens.cdpDebtToken),
      cooldown,
      incentiveBps,
      address($liquity.stabilityPool),
      address($collateralRegistry),
      address($liquity.systemParams),
      stabilityPoolPercentage,
      maxIterations
    );
    vm.stopPrank();
  }

  function _configureReserveLiquidityStrategy(uint64 cooldown, uint32 incentiveBps) internal {
    require($liquidityStrategies.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: liquidity strategies not deployed");
    require($tokens.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: tokens not deployed");
    vm.startPrank($addresses.governance);
    $liquidityStrategies.reserveLiquidityStrategy.addPool(
      address($fpmm.fpmmReserve),
      address($tokens.cdpCollToken),
      cooldown,
      incentiveBps
    );
    $tokens.cdpCollToken.setMinter(address($liquidityStrategies.reserveLiquidityStrategy), true);
    $tokens.cdpCollToken.setBurner(address($liquidityStrategies.reserveLiquidityStrategy), true);
    vm.stopPrank();
  }

  function _deployCDPLiquidityStrategy() private {
    CDPLiquidityStrategy implementation = new CDPLiquidityStrategy(true);

    bytes memory initData = abi.encodeWithSelector(CDPLiquidityStrategy.initialize.selector, $addresses.governance);

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(implementation),
      address($liquidityStrategies.proxyAdmin),
      initData
    );

    $liquidityStrategies.cdpLiquidityStrategy = ICDPLiquidityStrategy(address(proxy));
  }

  function _deployReserveLiquidityStrategy() private {
    _deployReserve();

    ReserveLiquidityStrategy implementation = new ReserveLiquidityStrategy(true);

    bytes memory initData = abi.encodeWithSelector(
      ReserveLiquidityStrategy.initialize.selector,
      $addresses.governance,
      address($liquidityStrategies.reserve)
    );

    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      address(implementation),
      address($liquidityStrategies.proxyAdmin),
      initData
    );

    $liquidityStrategies.reserveLiquidityStrategy = IReserveLiquidityStrategy(address(proxy));

    vm.startPrank($addresses.governance);
    $liquidityStrategies.reserve.registerLiquidityStrategySpender(
      address($liquidityStrategies.reserveLiquidityStrategy)
    );
    vm.stopPrank();
  }

  function _deployReserve() private {
    require($tokens.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: tokens not deployed");
    ReserveV2 reserve = new ReserveV2(false);
    $liquidityStrategies.reserve = reserve;

    address[] memory stableAssets = new address[](1);
    stableAssets[0] = address($tokens.resDebtToken);

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address($tokens.resCollToken);

    address[] memory otherReserveAddresses = new address[](0);
    address[] memory liquidityStrategySpenders = new address[](0);
    address[] memory reserveManagerSpenders = new address[](0);
    reserve.initialize(
      stableAssets,
      collateralAssets,
      otherReserveAddresses,
      liquidityStrategySpenders,
      reserveManagerSpenders,
      $addresses.governance
    );
  }

  /* ============================================================ */
  /* ================ Upgradeability Test Helpers =============== */
  /* ============================================================ */

  /**
   * @notice Upgrades the CDPLiquidityStrategy to a new implementation
   * @param newImplementation The address of the new implementation
   */
  function _upgradeCDPLiquidityStrategy(address newImplementation) internal {
    require($liquidityStrategies.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: liquidity strategies not deployed");

    vm.prank($addresses.governance);
    $liquidityStrategies.proxyAdmin.upgrade(
      ITransparentUpgradeableProxy(address($liquidityStrategies.cdpLiquidityStrategy)),
      newImplementation
    );
  }

  /**
   * @notice Upgrades the ReserveLiquidityStrategy to a new implementation
   * @param newImplementation The address of the new implementation
   */
  function _upgradeReserveLiquidityStrategy(address newImplementation) internal {
    require($liquidityStrategies.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: liquidity strategies not deployed");

    vm.prank($addresses.governance);
    $liquidityStrategies.proxyAdmin.upgrade(
      ITransparentUpgradeableProxy(address($liquidityStrategies.reserveLiquidityStrategy)),
      newImplementation
    );
  }

  /**
   * @notice Gets the current implementation address of CDPLiquidityStrategy
   * @return The implementation address
   */
  function _getCDPLiquidityStrategyImplementation() internal view returns (address) {
    return
      $liquidityStrategies.proxyAdmin.getProxyImplementation(
        ITransparentUpgradeableProxy(address($liquidityStrategies.cdpLiquidityStrategy))
      );
  }

  /**
   * @notice Gets the current implementation address of ReserveLiquidityStrategy
   * @return The implementation address
   */
  function _getReserveLiquidityStrategyImplementation() internal view returns (address) {
    return
      $liquidityStrategies.proxyAdmin.getProxyImplementation(
        ITransparentUpgradeableProxy(address($liquidityStrategies.reserveLiquidityStrategy))
      );
  }

  /**
   * @notice Gets the ProxyAdmin contract
   * @return The ProxyAdmin
   */
  function _getProxyAdmin() internal view returns (ProxyAdmin) {
    return $liquidityStrategies.proxyAdmin;
  }
}
