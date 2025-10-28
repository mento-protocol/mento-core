// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IMedianDeltaBreaker } from "contracts/interfaces/IMedianDeltaBreaker.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";

contract MentoV2Deployer is TestStorage {
  bool private _brokerDeployed;
  bool private _reserveDeployed;
  bool private _oraclesDeployed;

  function _deployMentoV2() internal {
    if ($mentoV2.deployed) return;
    _deployReserve();
    _deployOracles();
    _deployBroker();
    _initializeAssets();
    $mentoV2.deployed = true;
  }

  function _deployReserve() private {
    require($tokens.deployed, "MENTO_V2_DEPLOYER: tokens not deployed");
    IReserve reserve = IReserve(deployCode("Reserve", abi.encode(true)));
    $mentoV2.reserve = reserve;

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

  function _deployOracles() private {
    $mentoV2.sortedOracles = ISortedOracles(deployCode("SortedOracles", abi.encode(true)));
    $mentoV2.sortedOracles.initialize(60 * 10);

    $mentoV2.exof_celo_referenceRateFeedID = address($tokens.exof);
    $mentoV2.exof_usdm_referenceRateFeedID = address(bytes20(keccak256("XOF/USDm")));

    _configureOracleRate($mentoV2.exof_celo_referenceRateFeedID, 72e20);
    _configureOracleRate($mentoV2.exof_usdm_referenceRateFeedID, 18e20);

    address[] memory rateFeedIDs = new address[](2);
    rateFeedIDs[0] = $mentoV2.exof_celo_referenceRateFeedID;
    rateFeedIDs[1] = $mentoV2.exof_usdm_referenceRateFeedID;

    $mentoV2.breakerBox = IBreakerBox(
      deployCode("BreakerBox", abi.encode(rateFeedIDs, $mentoV2.sortedOracles, $addresses.governance))
    );
    $mentoV2.sortedOracles.setBreakerBox($mentoV2.breakerBox);

    address[] memory medianDeltaBreakerRateFeedIDs = new address[](2);
    medianDeltaBreakerRateFeedIDs[0] = $mentoV2.exof_celo_referenceRateFeedID;
    medianDeltaBreakerRateFeedIDs[1] = $mentoV2.exof_usdm_referenceRateFeedID;

    uint256[] memory medianDeltaBreakerRateChangeThresholds = new uint256[](2);
    medianDeltaBreakerRateChangeThresholds[0] = 1e22;
    medianDeltaBreakerRateChangeThresholds[1] = 1e22;
    uint256[] memory medianDeltaBreakerCooldownTimes = new uint256[](2);
    medianDeltaBreakerCooldownTimes[0] = 5 minutes;
    medianDeltaBreakerCooldownTimes[1] = 0;

    uint256 medianDeltaBreakerDefaultThreshold = 1e22;
    uint256 medianDeltaBreakerDefaultCooldown = 0;

    $mentoV2.medianDeltaBreaker = IMedianDeltaBreaker(
      deployCode(
        "MedianDeltaBreaker",
        abi.encode(
          medianDeltaBreakerDefaultCooldown,
          medianDeltaBreakerDefaultThreshold,
          $mentoV2.sortedOracles,
          address($mentoV2.breakerBox),
          medianDeltaBreakerRateFeedIDs,
          medianDeltaBreakerRateChangeThresholds,
          medianDeltaBreakerCooldownTimes,
          $addresses.governance
        )
      )
    );

    vm.startPrank($addresses.governance);
    $mentoV2.breakerBox.addBreaker(address($mentoV2.medianDeltaBreaker), 3);
    $mentoV2.breakerBox.toggleBreaker(
      address($mentoV2.medianDeltaBreaker),
      $mentoV2.exof_celo_referenceRateFeedID,
      true
    );
    $mentoV2.breakerBox.toggleBreaker(
      address($mentoV2.medianDeltaBreaker),
      $mentoV2.exof_usdm_referenceRateFeedID,
      true
    );
    vm.stopPrank();
    _oraclesDeployed = true;
  }

  function _deployBroker() private {
    require(_reserveDeployed, "MENTO_V2_DEPLOYER: Reserve must be deployed before the Broker");
    require(_oraclesDeployed, "MENTO_V2_DEPLOYER: Oracles must be deployed before the Broker");
    vm.startPrank($addresses.governance);
    $mentoV2.broker = IBroker(deployCode("Broker", abi.encode(true)));
    $mentoV2.constantProduct = IPricingModule(deployCode("ConstantProductPricingModule"));
    $mentoV2.biPoolManager = IBiPoolManager(deployCode("BiPoolManager", abi.encode(true)));

    bytes32[] memory pricingModuleIdentifiers = new bytes32[](1);
    pricingModuleIdentifiers[0] = keccak256(abi.encodePacked($mentoV2.constantProduct.name()));

    address[] memory pricingModules = new address[](1);
    pricingModules[0] = address($mentoV2.constantProduct);

    $mentoV2.biPoolManager.initialize(
      address($mentoV2.broker),
      IReserve($mentoV2.reserve),
      ISortedOracles(address($mentoV2.sortedOracles)),
      IBreakerBox(address($mentoV2.breakerBox))
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
    pair_exof_celo.config.referenceRateFeedID = $mentoV2.exof_celo_referenceRateFeedID;
    pair_exof_celo.config.stablePoolResetSize = 1e24;

    $mentoV2.pair_exof_celo_id = $mentoV2.biPoolManager.createExchange(pair_exof_celo);

    IBiPoolManager.PoolExchange memory pair_exof_usdm;
    pair_exof_usdm.asset0 = address($tokens.exof);
    pair_exof_usdm.asset1 = address($tokens.usdm);
    pair_exof_usdm.pricingModule = $mentoV2.constantProduct;
    pair_exof_usdm.lastBucketUpdate = block.timestamp;
    pair_exof_usdm.config.spread = FixidityLib.newFixedFraction(5, 100);
    pair_exof_usdm.config.referenceRateResetFrequency = 60 * 5;
    pair_exof_usdm.config.minimumReports = 1;
    pair_exof_usdm.config.referenceRateFeedID = $mentoV2.exof_usdm_referenceRateFeedID;
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
    $mentoV2.sortedOracles.addOracle(id, oracleAddress);
    vm.startPrank(oracleAddress);
    $mentoV2.sortedOracles.report(id, medianRate, address(0), address(0));
    vm.stopPrank();
  }
}
