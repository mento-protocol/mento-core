// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TestStorage } from "test/integration/v3/TestStorage.sol";
import { CDPLiquidityStrategy } from "contracts/liquidityStrategies/CDPLiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { ReserveLiquidityStrategy } from "contracts/liquidityStrategies/ReserveLiquidityStrategy.sol";
import { IReserveLiquidityStrategy } from "contracts/interfaces/IReserveLiquidityStrategy.sol";
import { ReserveV2 } from "contracts/swap/ReserveV2.sol";

contract LiquidityStrategyDeployer is TestStorage {
  function _deployLiquidityStrategies() internal {
    _deployCDPLiquidityStrategy();
    _deployReserveLiquidityStrategy();
    $liquidityStrategies.deployed = true;
    vm.label(address($liquidityStrategies.cdpLiquidityStrategy), "CDPLiquidityStrategy");
    vm.label(address($liquidityStrategies.reserveLiquidityStrategy), "ReserveLiquidityStrategy");
    vm.label(address($liquidityStrategies.reserve), "Reserve");
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
    CDPLiquidityStrategy newCDPLiquidityStrategy = new CDPLiquidityStrategy($addresses.governance);
    $liquidityStrategies.cdpLiquidityStrategy = ICDPLiquidityStrategy(address(newCDPLiquidityStrategy));
  }

  function _deployReserveLiquidityStrategy() private {
    _deployReserve();
    ReserveLiquidityStrategy newReserveLiquidityStrategy = new ReserveLiquidityStrategy(
      $addresses.governance,
      address($liquidityStrategies.reserve)
    );
    $liquidityStrategies.reserveLiquidityStrategy = IReserveLiquidityStrategy(address(newReserveLiquidityStrategy));
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
}
