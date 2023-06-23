// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { console } from "forge-std/console.sol";
import { Factory } from "./Factory.sol";

import { MockSortedOracles } from "../mocks/MockSortedOracles.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";

import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { Freezer } from "contracts/common/Freezer.sol";
import { AddressSortedLinkedListWithMedian } from "contracts/common/linkedlists/AddressSortedLinkedListWithMedian.sol";
import { SortedLinkedListWithMedian } from "contracts/common/linkedlists/SortedLinkedListWithMedian.sol";

import { BiPoolManager } from "contracts/swap/BiPoolManager.sol";
import { Broker } from "contracts/swap/Broker.sol";
import { ConstantProductPricingModule } from "contracts/swap/ConstantProductPricingModule.sol";
import { ConstantSumPricingModule } from "contracts/swap/ConstantSumPricingModule.sol";
import { Reserve } from "contracts/swap/Reserve.sol";
import { SortedOracles } from "contracts/oracles/SortedOracles.sol";
import { BreakerBox } from "contracts/oracles/BreakerBox.sol";
import { MedianDeltaBreaker } from "contracts/oracles/breakers/MedianDeltaBreaker.sol";
import { TradingLimits } from "contracts/libraries/TradingLimits.sol";

import { Token } from "./Token.sol";
import { BaseTest } from "./BaseTest.t.sol";

contract IntegrationTest is BaseTest {
  using FixidityLib for FixidityLib.Fraction;
  using AddressSortedLinkedListWithMedian for SortedLinkedListWithMedian.List;
  using TradingLimits for TradingLimits.Config;

  uint256 constant tobinTaxStalenessThreshold = 600;
  uint256 constant dailySpendingRatio = 1000000000000000000000000;
  uint256 constant sortedOraclesDenominator = 1000000000000000000000000;
  uint256 tobinTax = FixidityLib.newFixedFraction(5, 1000).unwrap();
  uint256 tobinTaxReserveRatio = FixidityLib.newFixedFraction(2, 1).unwrap();

  event BucketsUpdated(bytes32 indexed exchangeId, uint256 bucket0, uint256 bucket1);

  mapping(address => uint256) oracleCounts;

  Broker broker;
  BiPoolManager biPoolManager;
  Reserve reserve;
  IPricingModule constantProduct;
  IPricingModule constantSum;

  SortedOracles sortedOracles;
  BreakerBox breakerBox;
  MedianDeltaBreaker medianDeltaBreaker;

  Token celoToken;
  Token usdcToken;
  IStableTokenV2 cUSDToken;
  IStableTokenV2 cEURToken;
  Freezer freezer;

  address cUSD_CELO_referenceRateFeedID;
  address cEUR_CELO_referenceRateFeedID;
  address cUSD_bridgedUSDC_referenceRateFeedID;
  address cEUR_bridgedUSDC_referenceRateFeedID;
  address cUSD_cEUR_referenceRateFeedID;

  bytes32 pair_cUSD_CELO_ID;
  bytes32 pair_cEUR_CELO_ID;
  bytes32 pair_cUSD_bridgedUSDC_ID;
  bytes32 pair_cEUR_bridgedUSDC_ID;
  bytes32 pair_cUSD_cEUR_ID;

  function setUp() public {
    vm.warp(60 * 60 * 24 * 10); // Start at a non-zero timestamp.
    vm.startPrank(deployer);
    broker = new Broker(true);

    setUp_assets();
    setUp_reserve();
    setUp_sortedOracles();
    setUp_breakers();
    setUp_broker();
    setUp_freezer();
    setUp_tradingLimits();
  }

  function setUp_assets() internal {
    /* ===== Deploy collateral and stable assets ===== */

    celoToken = new Token("Celo", "cGLD", 18);
    usdcToken = new Token("bridgedUSDC", "bridgedUSDC", 6);

    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);

    cUSDToken = IStableTokenV2(factory.create("StableTokenV2", abi.encode(false)));
    cUSDToken.initialize(
      "cUSD",
      "cUSD",
      18,
      REGISTRY_ADDRESS,
      FixidityLib.unwrap(FixidityLib.fixed1()),
      60 * 60 * 24 * 7,
      initialAddresses,
      initialBalances,
      "Exchange"
    );
    cUSDToken.initializeV2(address(broker), address(0x0), address(0x0));

    cEURToken = IStableTokenV2(factory.create("StableTokenV2", abi.encode(false)));
    cEURToken.initialize(
      "cEUR",
      "cEUR",
      18,
      REGISTRY_ADDRESS,
      FixidityLib.unwrap(FixidityLib.fixed1()),
      60 * 60 * 24 * 7,
      initialAddresses,
      initialBalances,
      "Exchange"
    );
    cEURToken.initializeV2(address(broker), address(0x0), address(0x0));

    vm.label(address(cUSDToken), "cUSD");
    vm.label(address(cEURToken), "cEUR");
  }

  function setUp_reserve() internal {
    changePrank(deployer);
    /* ===== Deploy reserve ===== */

    bytes32[] memory initialAssetAllocationSymbols = new bytes32[](2);
    uint256[] memory initialAssetAllocationWeights = new uint256[](2);
    initialAssetAllocationSymbols[0] = bytes32("cGLD");
    initialAssetAllocationWeights[0] = FixidityLib.newFixedFraction(1, 2).unwrap();
    initialAssetAllocationSymbols[1] = bytes32("bridgedUSDC");
    initialAssetAllocationWeights[1] = FixidityLib.newFixedFraction(1, 2).unwrap();

    address[] memory asse1s = new address[](2);
    uint256[] memory asse1DailySpendingRatios = new uint256[](2);
    asse1s[0] = address(celoToken);
    asse1DailySpendingRatios[0] = 100000000000000000000000;
    asse1s[1] = address(usdcToken);
    asse1DailySpendingRatios[1] = 100000000000000000000000;

    reserve = new Reserve(true);
    reserve.initialize(
      REGISTRY_ADDRESS,
      tobinTaxStalenessThreshold,
      dailySpendingRatio,
      0,
      0,
      initialAssetAllocationSymbols,
      initialAssetAllocationWeights,
      tobinTax,
      tobinTaxReserveRatio,
      asse1s,
      asse1DailySpendingRatios
    );

    reserve.addToken(address(cUSDToken));
    reserve.addToken(address(cEURToken));
  }

  function setUp_sortedOracles() internal {
    changePrank(deployer);
    /* ===== Deploy SortedOracles ===== */

    sortedOracles = new SortedOracles(true);
    sortedOracles.initialize(60 * 10);

    cUSD_CELO_referenceRateFeedID = address(cUSDToken);
    cEUR_CELO_referenceRateFeedID = address(cEURToken);
    cUSD_bridgedUSDC_referenceRateFeedID = address(bytes20(keccak256("USD/USDC")));
    cEUR_bridgedUSDC_referenceRateFeedID = address(bytes20(keccak256("EUR/USDC")));
    cUSD_cEUR_referenceRateFeedID = address(bytes20(keccak256("USD/EUR")));

    initOracles(cUSD_CELO_referenceRateFeedID, 10);
    setMedianRate(cUSD_CELO_referenceRateFeedID, 5e23);

    initOracles(cEUR_CELO_referenceRateFeedID, 10);
    setMedianRate(cEUR_CELO_referenceRateFeedID, 5e23);

    initOracles(cUSD_bridgedUSDC_referenceRateFeedID, 10);
    setMedianRate(cUSD_bridgedUSDC_referenceRateFeedID, 1 * 1e24);

    initOracles(cEUR_bridgedUSDC_referenceRateFeedID, 10);
    setMedianRate(cEUR_bridgedUSDC_referenceRateFeedID, 0.9 * 1e24);

    initOracles(cUSD_cEUR_referenceRateFeedID, 10);
    setMedianRate(cUSD_cEUR_referenceRateFeedID, 1.1 * 1e24);
  }

  function initOracles(address rateFeedID, uint256 count) internal {
    oracleCounts[rateFeedID] = count;
    for (uint256 oracleIndex = 0; oracleIndex < count; oracleIndex++) {
      address oracleAddy = getOracleAddy(rateFeedID, oracleIndex);
      sortedOracles.addOracle(rateFeedID, oracleAddy);
    }
  }

  function setMedianRate(address rateFeedID, uint256 rate) internal {
    uint256 count = oracleCounts[rateFeedID];
    for (uint256 oracleIndex = 0; oracleIndex < count; oracleIndex++) {
      address oracleAddy = getOracleAddy(rateFeedID, oracleIndex);
      address lesserKey;
      address greaterKey;
      (address[] memory keys, uint256[] memory values, ) = sortedOracles.getRates(rateFeedID);
      for (uint256 i = 0; i < keys.length; i++) {
        if (keys[i] == oracleAddy) continue;
        if (values[i] < rate) lesserKey = keys[i];
        if (values[i] >= rate) greaterKey = keys[i];
      }

      changePrank(oracleAddy);
      sortedOracles.report(rateFeedID, rate, lesserKey, greaterKey);
      changePrank(deployer);
    }
  }

  function getOracleAddy(address rateFeedID, uint256 oracleIndex) internal pure returns (address) {
    return vm.addr(uint256(keccak256(abi.encodePacked(rateFeedID, oracleIndex))));
  }

  function setUp_breakers() internal {
    /* ========== Deploy Breaker Box =============== */
    address[] memory rateFeedIDs = new address[](5);
    rateFeedIDs[0] = cUSD_CELO_referenceRateFeedID;
    rateFeedIDs[1] = cEUR_CELO_referenceRateFeedID;
    rateFeedIDs[2] = cUSD_bridgedUSDC_referenceRateFeedID;
    rateFeedIDs[3] = cEUR_bridgedUSDC_referenceRateFeedID;
    rateFeedIDs[4] = cUSD_cEUR_referenceRateFeedID;

    breakerBox = new BreakerBox(rateFeedIDs, ISortedOracles(address(sortedOracles)));

    /* ========== Deploy Median Delta Breaker =============== */

    // todo change these to correct values
    uint256[] memory rateChangeThresholds = new uint256[](5);
    uint256[] memory cooldownTimes = new uint256[](5);

    rateChangeThresholds[0] = 0.15 * 10**24;
    rateChangeThresholds[1] = 0.14 * 10**24;
    rateChangeThresholds[2] = 0.13 * 10**24;
    rateChangeThresholds[3] = 0.12 * 10**24;
    rateChangeThresholds[4] = 0.11 * 10**24;

    uint256 threshold = 0.15 * 10**24; // 15%
    uint256 coolDownTime = 5 minutes;

    medianDeltaBreaker = new MedianDeltaBreaker(
      coolDownTime,
      threshold,
      ISortedOracles(address(sortedOracles)),
      rateFeedIDs,
      rateChangeThresholds,
      cooldownTimes
    );

    breakerBox.addBreaker(address(medianDeltaBreaker), 1);
    sortedOracles.setBreakerBox(breakerBox);

    // enable breakers
    breakerBox.toggleBreaker(address(medianDeltaBreaker), cUSD_CELO_referenceRateFeedID, true);
    breakerBox.toggleBreaker(address(medianDeltaBreaker), cEUR_CELO_referenceRateFeedID, true);
    breakerBox.toggleBreaker(address(medianDeltaBreaker), cUSD_bridgedUSDC_referenceRateFeedID, true);
    breakerBox.toggleBreaker(address(medianDeltaBreaker), cUSD_cEUR_referenceRateFeedID, true);
    breakerBox.toggleBreaker(address(medianDeltaBreaker), cEUR_bridgedUSDC_referenceRateFeedID, true);
  }

  function setUp_broker() internal {
    /* ===== Deploy BiPoolManager & Broker ===== */

    constantProduct = new ConstantProductPricingModule();
    constantSum = new ConstantSumPricingModule();
    biPoolManager = new BiPoolManager(true);

    biPoolManager.initialize(
      address(broker),
      IReserve(reserve),
      ISortedOracles(address(sortedOracles)),
      IBreakerBox(address(breakerBox))
    );
    address[] memory exchangeProviders = new address[](1);
    exchangeProviders[0] = address(biPoolManager);

    broker.initialize(exchangeProviders, address(reserve));
    registry.setAddressFor("Broker", address(broker));
    reserve.addExchangeSpender(address(broker));

    /* ====== Create pairs for all asset combinations ======= */

    BiPoolManager.PoolExchange memory pair_cUSD_CELO;
    pair_cUSD_CELO.asset0 = address(cUSDToken);
    pair_cUSD_CELO.asset1 = address(celoToken);
    pair_cUSD_CELO.pricingModule = constantProduct;
    pair_cUSD_CELO.lastBucketUpdate = now;
    pair_cUSD_CELO.config.spread = FixidityLib.newFixedFraction(5, 100);
    pair_cUSD_CELO.config.referenceRateResetFrequency = 60 * 5;
    pair_cUSD_CELO.config.minimumReports = 5;
    pair_cUSD_CELO.config.referenceRateFeedID = cUSD_CELO_referenceRateFeedID;
    pair_cUSD_CELO.config.stablePoolResetSize = 1e24;

    pair_cUSD_CELO_ID = biPoolManager.createExchange(pair_cUSD_CELO);

    BiPoolManager.PoolExchange memory pair_cEUR_CELO;
    pair_cEUR_CELO.asset0 = address(cEURToken);
    pair_cEUR_CELO.asset1 = address(celoToken);
    pair_cEUR_CELO.pricingModule = constantProduct;
    pair_cEUR_CELO.lastBucketUpdate = now;
    pair_cEUR_CELO.config.spread = FixidityLib.newFixedFraction(5, 100);
    pair_cEUR_CELO.config.referenceRateResetFrequency = 60 * 5;
    pair_cEUR_CELO.config.minimumReports = 5;
    pair_cEUR_CELO.config.referenceRateFeedID = cEUR_CELO_referenceRateFeedID;
    pair_cEUR_CELO.config.stablePoolResetSize = 1e24;

    pair_cEUR_CELO_ID = biPoolManager.createExchange(pair_cEUR_CELO);

    BiPoolManager.PoolExchange memory pair_cUSD_bridgedUSDC;
    pair_cUSD_bridgedUSDC.asset0 = address(cUSDToken);
    pair_cUSD_bridgedUSDC.asset1 = address(usdcToken);
    pair_cUSD_bridgedUSDC.pricingModule = constantSum;
    pair_cUSD_bridgedUSDC.lastBucketUpdate = now;
    pair_cUSD_bridgedUSDC.config.spread = FixidityLib.newFixedFraction(5, 1000);
    pair_cUSD_bridgedUSDC.config.referenceRateResetFrequency = 60 * 5;
    pair_cUSD_bridgedUSDC.config.minimumReports = 5;
    pair_cUSD_bridgedUSDC.config.referenceRateFeedID = cUSD_bridgedUSDC_referenceRateFeedID;
    pair_cUSD_bridgedUSDC.config.stablePoolResetSize = 1e24;

    pair_cUSD_bridgedUSDC_ID = biPoolManager.createExchange(pair_cUSD_bridgedUSDC);

    BiPoolManager.PoolExchange memory pair_cEUR_bridgedUSDC;
    pair_cEUR_bridgedUSDC.asset0 = address(cEURToken);
    pair_cEUR_bridgedUSDC.asset1 = address(usdcToken);
    pair_cEUR_bridgedUSDC.pricingModule = constantProduct;
    pair_cEUR_bridgedUSDC.lastBucketUpdate = now;
    pair_cEUR_bridgedUSDC.config.spread = FixidityLib.newFixedFraction(5, 100);
    pair_cEUR_bridgedUSDC.config.referenceRateResetFrequency = 60 * 5;
    pair_cEUR_bridgedUSDC.config.minimumReports = 5;
    pair_cEUR_bridgedUSDC.config.referenceRateFeedID = cEUR_bridgedUSDC_referenceRateFeedID;
    pair_cEUR_bridgedUSDC.config.stablePoolResetSize = 1e24;

    pair_cEUR_bridgedUSDC_ID = biPoolManager.createExchange(pair_cEUR_bridgedUSDC);

    BiPoolManager.PoolExchange memory pair_cUSD_cEUR;
    pair_cUSD_cEUR.asset0 = address(cUSDToken);
    pair_cUSD_cEUR.asset1 = address(cEURToken);
    pair_cUSD_cEUR.pricingModule = constantProduct;
    pair_cUSD_cEUR.lastBucketUpdate = now;
    pair_cUSD_cEUR.config.spread = FixidityLib.newFixedFraction(5, 100);
    pair_cUSD_cEUR.config.referenceRateResetFrequency = 60 * 5;
    pair_cUSD_cEUR.config.minimumReports = 5;
    pair_cUSD_cEUR.config.referenceRateFeedID = cUSD_cEUR_referenceRateFeedID;
    pair_cUSD_cEUR.config.stablePoolResetSize = 1e24;

    pair_cUSD_cEUR_ID = biPoolManager.createExchange(pair_cUSD_cEUR);
  }

  function setUp_freezer() internal {
    /* ========== Deploy Freezer =============== */

    freezer = new Freezer(true);
    registry.setAddressFor("Freezer", address(freezer));
  }

  function setUp_tradingLimits() internal {
    /* ========== Config Trading Limits =============== */
    TradingLimits.Config memory config = configL0L1LG(100, 10000, 1000, 100000, 1000000);
    broker.configureTradingLimit(pair_cUSD_CELO_ID, address(cUSDToken), config);
    broker.configureTradingLimit(pair_cEUR_CELO_ID, address(cEURToken), config);
    broker.configureTradingLimit(pair_cUSD_bridgedUSDC_ID, address(usdcToken), config);
    broker.configureTradingLimit(pair_cEUR_bridgedUSDC_ID, address(usdcToken), config);
    broker.configureTradingLimit(pair_cUSD_cEUR_ID, address(cUSDToken), config);
  }

  function configL0L1LG(
    uint32 timestep0,
    int48 limit0,
    uint32 timestep1,
    int48 limit1,
    int48 limitGlobal
  ) internal pure returns (TradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.limitGlobal = limitGlobal;
    config.flags = 1 | 2 | 4; //L0, L1, and LG
  }
}
