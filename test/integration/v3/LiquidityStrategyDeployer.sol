// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TestStorage } from "test/integration/v3/TestStorage.sol";
import { CDPLiquidityStrategy } from "contracts/liquidityStrategies/CDPLiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { ReserveLiquidityStrategy } from "contracts/liquidityStrategies/ReserveLiquidityStrategy.sol";
import { IReserveLiquidityStrategy } from "contracts/interfaces/IReserveLiquidityStrategy.sol";

contract LiquidityStrategyDeployer is TestStorage {
  function _deployLiquidityStrategies() internal {
    require($mentoV2.deployed, "Mento V2 (Reserve) needs to be deployed first");
    _deployCDPLiquidityStrategy();
    _deployReserveLiquidityStrategy();
    $liquidityStrategies.deployed = true;
    vm.label(address($liquidityStrategies.cdpLiquidityStrategy), "CDPLiquidityStrategy");
    vm.label(address($liquidityStrategies.reserveLiquidityStrategy), "ReserveLiquidityStrategy");
    vm.label(address($mentoV2.reserve), "Reserve");
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
      address($tokens.eurm),
      cooldown,
      incentiveBps,
      address($liquity.stabilityPool),
      address($liquity.collateralRegistry),
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
      address($tokens.usdm),
      cooldown,
      incentiveBps
    );
    $tokens.usdm.setMinter(address($liquidityStrategies.reserveLiquidityStrategy), true);
    $tokens.usdm.setBurner(address($liquidityStrategies.reserveLiquidityStrategy), true);
    vm.stopPrank();
  }

  function _deployCDPLiquidityStrategy() private {
    CDPLiquidityStrategy newCDPLiquidityStrategy = new CDPLiquidityStrategy($addresses.governance);
    $liquidityStrategies.cdpLiquidityStrategy = ICDPLiquidityStrategy(address(newCDPLiquidityStrategy));
  }

  function _deployReserveLiquidityStrategy() private {
    require($mentoV2.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: MentoV2 (Reserve) not deployed");
    ReserveLiquidityStrategy newReserveLiquidityStrategy = new ReserveLiquidityStrategy(
      $addresses.governance,
      address($mentoV2.reserve)
    );
    $liquidityStrategies.reserveLiquidityStrategy = IReserveLiquidityStrategy(address(newReserveLiquidityStrategy));
    vm.startPrank($addresses.governance);
    $mentoV2.reserve.addExchangeSpender(address($liquidityStrategies.reserveLiquidityStrategy));
    vm.stopPrank();
  }
}
