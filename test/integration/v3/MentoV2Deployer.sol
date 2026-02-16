// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";

contract MentoV2Deployer is TestStorage {
  bool private _brokerDeployed;
  bool private _reserveDeployed;
  bool private _oraclesConfigured;

  function _deployMentoV2() internal {
    if ($mentoV2.deployed) return;
    _deployReserveV1();
    _configureOracles();
    _deployBroker();
    _initializeAssets();
    $mentoV2.deployed = true;
  }

  function _deployReserveV1() private {
    require($tokens.deployed, "MENTO_V2_DEPLOYER: tokens not deployed");
    IReserve reserve = IReserve(deployCode("Reserve", abi.encode(true)));
    $mentoV2.reserve = reserve;
    vm.label(address(reserve), "Reserve");

    vm.startPrank($addresses.governance);
    bytes32[] memory initialAssetAllocationSymbols = new bytes32[](2);
    initialAssetAllocationSymbols[0] = bytes32("cGLD");
    initialAssetAllocationSymbols[1] = bytes32("cUSD");

    uint256[] memory initialAssetAllocationWeights = new uint256[](2);
    initialAssetAllocationWeights[0] = 5e23;
    initialAssetAllocationWeights[1] = 5e23;

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address($tokens.usdc);

    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssetDailySpendingRatios[0] = 1e24;

    reserve.initialize({
      registryAddress: makeAddr("registry"),
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
    reserve.addToken(address($tokens.usdm));
    reserve.addToken(address($tokens.exof));
    reserve.addCollateralAsset(address($tokens.usdc));
    reserve.addCollateralAsset(address($tokens.celo));
    vm.stopPrank();
    _reserveDeployed = true;
  }

  function _configureOracles() private {
    require($oracle.deployed, "MentoV2Deployer: OracleAdapter must be deployed first");

    _configureOracleRate($addresses.referenceRateFeedeXOFCELO, 72e20);
    _configureOracleRate($addresses.referenceRateFeedeXOFUSD, 18e20);

    address[] memory rateFeedIDs = new address[](2);
    rateFeedIDs[0] = $addresses.referenceRateFeedeXOFCELO;
    rateFeedIDs[1] = $addresses.referenceRateFeedeXOFUSD;

    address[] memory medianDeltaBreakerRateFeedIDs = new address[](2);
    medianDeltaBreakerRateFeedIDs[0] = $addresses.referenceRateFeedeXOFCELO;
    medianDeltaBreakerRateFeedIDs[1] = $addresses.referenceRateFeedeXOFUSD;

    uint256[] memory medianDeltaBreakerRateChangeThresholds = new uint256[](2);
    medianDeltaBreakerRateChangeThresholds[0] = 1e22;
    medianDeltaBreakerRateChangeThresholds[1] = 1e22;
    uint256[] memory medianDeltaBreakerCooldownTimes = new uint256[](2);
    medianDeltaBreakerCooldownTimes[0] = 5 minutes;
    medianDeltaBreakerCooldownTimes[1] = 0;

    vm.startPrank($addresses.governance);
    $oracle.breakerBox.addRateFeeds(medianDeltaBreakerRateFeedIDs);

    $oracle.medianDeltaBreaker.setCooldownTime(medianDeltaBreakerRateFeedIDs, medianDeltaBreakerCooldownTimes);
    $oracle.medianDeltaBreaker.setRateChangeThresholds(
      medianDeltaBreakerRateFeedIDs,
      medianDeltaBreakerRateChangeThresholds
    );

    $oracle.breakerBox.toggleBreaker(address($oracle.medianDeltaBreaker), $addresses.referenceRateFeedeXOFCELO, true);
    $oracle.breakerBox.toggleBreaker(address($oracle.medianDeltaBreaker), $addresses.referenceRateFeedeXOFUSD, true);
    vm.stopPrank();
    _oraclesConfigured = true;
  }

  function _deployBroker() private {
    require(_reserveDeployed, "MENTO_V2_DEPLOYER: Reserve must be deployed before");
    require(_oraclesConfigured, "MENTO_V2_DEPLOYER: Oracles must be configured before");
    vm.startPrank($addresses.governance);
    $mentoV2.broker = IBroker(deployCode("Broker", abi.encode(true)));
    $mentoV2.constantProduct = IPricingModule(deployCode("ConstantProductPricingModule"));
    $mentoV2.constantSum = IPricingModule(deployCode("ConstantSumPricingModule"));
    $mentoV2.biPoolManager = IBiPoolManager(deployCode("BiPoolManager", abi.encode(true)));

    bytes32[] memory pricingModuleIdentifiers = new bytes32[](2);
    pricingModuleIdentifiers[0] = keccak256(abi.encodePacked($mentoV2.constantProduct.name()));
    pricingModuleIdentifiers[1] = keccak256(abi.encodePacked($mentoV2.constantSum.name()));

    address[] memory pricingModules = new address[](2);
    pricingModules[0] = address($mentoV2.constantProduct);
    pricingModules[1] = address($mentoV2.constantSum);

    $mentoV2.biPoolManager.initialize(
      address($mentoV2.broker),
      IReserve($mentoV2.reserve),
      ISortedOracles(address($oracle.sortedOracles)),
      IBreakerBox(address($oracle.breakerBox))
    );
    address[] memory exchangeProviders = new address[](1);
    exchangeProviders[0] = address($mentoV2.biPoolManager);

    address[] memory reserves = new address[](1);
    reserves[0] = address($mentoV2.reserve);

    $mentoV2.broker.initialize(exchangeProviders, reserves);
    $mentoV2.reserve.addExchangeSpender(address($mentoV2.broker));
    $mentoV2.biPoolManager.setPricingModules(pricingModuleIdentifiers, pricingModules);

    IBiPoolManager.PoolExchange memory pair_exof_celo;
    pair_exof_celo.asset0 = address($tokens.exof);
    pair_exof_celo.asset1 = address($tokens.celo);
    pair_exof_celo.pricingModule = $mentoV2.constantProduct;
    pair_exof_celo.lastBucketUpdate = block.timestamp;
    pair_exof_celo.config.spread = FixidityLib.newFixedFraction(5, 100);
    pair_exof_celo.config.referenceRateResetFrequency = 60 * 5;
    pair_exof_celo.config.minimumReports = 1;
    pair_exof_celo.config.referenceRateFeedID = $addresses.referenceRateFeedeXOFCELO;
    pair_exof_celo.config.stablePoolResetSize = 1e24;

    $mentoV2.pair_exof_celo_id = $mentoV2.biPoolManager.createExchange(pair_exof_celo);

    IBiPoolManager.PoolExchange memory pair_exof_usdm;
    pair_exof_usdm.asset0 = address($tokens.exof);
    pair_exof_usdm.asset1 = address($tokens.usdm);
    pair_exof_usdm.pricingModule = $mentoV2.constantSum;
    pair_exof_usdm.lastBucketUpdate = block.timestamp;
    pair_exof_usdm.config.spread = FixidityLib.newFixedFraction(5, 100);
    pair_exof_usdm.config.referenceRateResetFrequency = 60 * 5;
    pair_exof_usdm.config.minimumReports = 1;
    pair_exof_usdm.config.referenceRateFeedID = $addresses.referenceRateFeedeXOFUSD;
    pair_exof_usdm.config.stablePoolResetSize = 1e24;

    $mentoV2.pair_exof_usdm_id = $mentoV2.biPoolManager.createExchange(pair_exof_usdm);
    vm.stopPrank();
  }

  function _initializeAssets() private {
    vm.startPrank($addresses.governance);
    $tokens.exof.initializeV2(address($mentoV2.broker), address(0), address(0));
    vm.stopPrank();
  }

  function _configureOracleRate(address id, uint256 medianRate) internal {
    address oracleAddress = vm.addr(uint256(keccak256(abi.encode(id))));
    vm.prank($addresses.governance);
    $oracle.sortedOracles.addOracle(id, oracleAddress);
    vm.prank(oracleAddress);
    $oracle.sortedOracles.report(id, medianRate, address(0), address(0));
  }
}
