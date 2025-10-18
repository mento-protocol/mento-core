// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TestStorage } from "test/integration/v3/TestStorage.sol";
import { CDPLiquidityStrategy } from "contracts/liquidityStrategies/CDPLiquidityStrategy.sol";
import { ICDPLiquidityStrategy } from "contracts/interfaces/ICDPLiquidityStrategy.sol";
import { ReserveLiquidityStrategy } from "contracts/liquidityStrategies/ReserveLiquidityStrategy.sol";
import { IReserveLiquidityStrategy } from "contracts/interfaces/IReserveLiquidityStrategy.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";

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

    $liquidityStrategies.cdpLiquidityStrategy.addPool(
      address($fpmm.fpmmCDP),
      address($tokens.debtToken),
      cooldown,
      incentiveBps,
      address($liquity.stabilityPool),
      makeAddr("collateralRegistry"), // TODO: Deploy collateral registry
      address($liquity.systemParams),
      stabilityPoolPercentage,
      maxIterations
    );
  }

  function _configureReserveLiquidityStrategy(uint64 cooldown, uint32 incentiveBps) internal {
    require($liquidityStrategies.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: liquidity strategies not deployed");
    require($tokens.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: tokens not deployed");
    $liquidityStrategies.reserveLiquidityStrategy.addPool(
      address($fpmm.fpmmReserve),
      address($tokens.collateralToken),
      cooldown,
      incentiveBps
    );
    vm.startPrank($addresses.governance);
    $tokens.collateralToken.setMinter(address($liquidityStrategies.reserve), true);
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
    $liquidityStrategies.reserve.addExchangeSpender(address($liquidityStrategies.reserveLiquidityStrategy));
    vm.stopPrank();
  }
  function _deployReserve() private {
    require($tokens.deployed, "LIQUIDITY_STRATEGY_DEPLOYER: tokens not deployed");
    IReserve reserve = IReserve(deployCode("Reserve", abi.encode(true)));
    $liquidityStrategies.reserve = reserve;

    vm.startPrank($addresses.governance);
    bytes32[] memory initialAssetAllocationSymbols = new bytes32[](2);
    initialAssetAllocationSymbols[0] = bytes32("cGLD");
    initialAssetAllocationSymbols[1] = bytes32("cUSD");

    uint256[] memory initialAssetAllocationWeights = new uint256[](2);
    initialAssetAllocationWeights[0] = 5e23;
    initialAssetAllocationWeights[1] = 5e23;

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address($tokens.reserveCollateralToken);

    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssetDailySpendingRatios[0] = 1e24;

    reserve.initialize({
      registryAddress: address(makeAddr("registry")),
      _tobinTaxStalenessThreshold: 600,
      _spendingRatioForCelo: 1e24,
      _frozenGold: 0,
      _frozenDays: 0,
      _assetAllocationSymbols: initialAssetAllocationSymbols,
      _assetAllocationWeights: initialAssetAllocationWeights,
      _tobinTax: 5e21,
      _tobinTaxReserveRatio: 2e24,
      _collateralAssets: new address[](0),
      _collateralAssetDailySpendingRatios: new uint256[](0)
    });
    reserve.addToken(address($tokens.collateralToken));
    reserve.addCollateralAsset(address($tokens.reserveCollateralToken));
    vm.stopPrank();
  }
}
