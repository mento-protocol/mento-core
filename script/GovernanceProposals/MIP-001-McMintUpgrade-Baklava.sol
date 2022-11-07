// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "../ScriptHelper.sol";

import { Reserve } from "contracts/Reserve.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";
import { Broker } from "contracts/Broker.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";

import { StableTokenProxy } from "contracts/proxies/StableTokenProxy.sol";
import { StableTokenEURProxy } from "contracts/proxies/StableTokenEURProxy.sol";
import { StableTokenBRLProxy } from "contracts/proxies/StableTokenBRLProxy.sol";
import { ReserveProxy } from "contracts/proxies/ReserveProxy.sol";

// forge script script/GovernanceProposals/MIP-001-McMintUpgrade.sol --fork-url http://localhost:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
contract McMintUpgrade is Script, ScriptHelper {
  using FixidityLib for FixidityLib.Fraction;

  ReserveProxy reserveProxy;
  StableTokenProxy stableTokenProxy;
  StableTokenEURProxy stableTokenEURProxy;
  StableTokenBRLProxy stableTokenBRLProxy;

  IBiPoolManager biPoolManager;

  function run() public {
    uint256 deployNetwork = vm.envUint("DEPLOY_NETWORK");

    NetworkProxies memory proxies = getNetworkProxies(deployNetwork);
    NetworkImplementations memory implementations = getNetworkImplementations(deployNetwork);

    biPoolManager = IBiPoolManager(proxies.biPoolManager);

    reserveProxy = ReserveProxy(address(uint160(proxies.reserve)));
    stableTokenProxy = StableTokenProxy(address(uint160(proxies.stableToken)));
    stableTokenEURProxy = StableTokenEURProxy(address(uint160(proxies.stableTokenEUR)));
    stableTokenBRLProxy = StableTokenBRLProxy(address(uint160(proxies.stableTokenBRL)));

    vm.startBroadcast();
    {
      console2.log("Reserve proxy address: ", address(reserveProxy));
      // Update exisiting proxy implementations
      reserveProxy._setImplementation(implementations.reserve);
      // stableTokenProxy._setImplementation(implementations.stableToken);
      // stableTokenEURProxy._setImplementation(implementations.stableTokenEUR);
      // stableTokenBRLProxy._setImplementation(implementations.stableTokenBRL);
      // // Set broker as reserve spender
      // IReserve(proxies.reserve).addSpender(proxies.broker);
      // Add pools to the BiPoolManager: cUSD/CELO, cEUR/CELO, cREAL/CELO, cUSD/USDCet
      // BiPoolManager.PoolExchange memory pair_cUSD_CELO;
      // pair_cUSD_CELO.asset0 = proxies.stableToken;
      // pair_cUSD_CELO.asset1 = proxies.celoToken;
      // pair_cUSD_CELO.pricingModule = IPricingModule(implementations.constantProductPricingModule);
      // pair_cUSD_CELO.lastBucketUpdate = now;
      // pair_cUSD_CELO.config.spread = FixidityLib.newFixedFraction(5, 100);
      // pair_cUSD_CELO.config.referenceRateResetFrequency = 60 * 5;
      // pair_cUSD_CELO.config.minimumReports = 5;
      // pair_cUSD_CELO.config.oracleReportTarget = proxies.stableToken;
      // pair_cUSD_CELO.config.stablePoolResetSize = 1e24;
      // bytes32 pair_cUSD_CELO_ID = biPoolManager.createExchange(pair_cUSD_CELO);
      // BiPoolManager.PoolExchange memory pair_cEUR_CELO;
      // pair_cEUR_CELO.asset0 = proxies.stableTokenEUR;
      // pair_cEUR_CELO.asset1 = proxies.celoToken;
      // pair_cEUR_CELO.pricingModule = IPricingModule(implementations.constantProductPricingModule);
      // pair_cEUR_CELO.lastBucketUpdate = now;
      // pair_cEUR_CELO.config.spread = FixidityLib.newFixedFraction(5, 100);
      // pair_cEUR_CELO.config.referenceRateResetFrequency = 60 * 5;
      // pair_cEUR_CELO.config.minimumReports = 5;
      // pair_cEUR_CELO.config.oracleReportTarget = proxies.stableTokenEUR;
      // pair_cEUR_CELO.config.stablePoolResetSize = 1e24;
      // bytes32 pair_cEUR_CELO_ID = biPoolManager.createExchange(pair_cEUR_CELO);
      // BiPoolManager.PoolExchange memory pair_cBRL_CELO;
      // pair_cBRL_CELO.asset0 = proxies.stableTokenBRL;
      // pair_cBRL_CELO.asset1 = proxies.celoToken;
      // pair_cBRL_CELO.pricingModule = IPricingModule(implementations.constantProductPricingModule);
      // pair_cBRL_CELO.lastBucketUpdate = now;
      // pair_cBRL_CELO.config.spread = FixidityLib.newFixedFraction(5, 100);
      // pair_cBRL_CELO.config.referenceRateResetFrequency = 60 * 5;
      // pair_cBRL_CELO.config.minimumReports = 5;
      // pair_cBRL_CELO.config.oracleReportTarget = proxies.stableTokenBRL;
      // pair_cBRL_CELO.config.stablePoolResetSize = 1e24;
      // bytes32 pair_cBRL_CELO_ID = biPoolManager.createExchange(pair_cBRL_CELO);
      // BiPoolManager.PoolExchange memory pair_cUSD_USDCet;
      // pair_cUSD_USDCet.asset0 = implementations.usdcToken;
      // pair_cUSD_USDCet.asset1 = proxies.celoToken;
      // pair_cUSD_USDCet.pricingModule = IPricingModule(implementations.constantProductPricingModule);
      // pair_cUSD_USDCet.lastBucketUpdate = now;
      // pair_cUSD_USDCet.config.spread = FixidityLib.newFixedFraction(5, 100);
      // pair_cUSD_USDCet.config.referenceRateResetFrequency = 60 * 5;
      // pair_cUSD_USDCet.config.minimumReports = 5;
      // pair_cUSD_USDCet.config.oracleReportTarget = proxies.stableToken;
      // pair_cUSD_USDCet.config.stablePoolResetSize = 1e24;
      // bytes32 pair_cUSD_USDCet_ID = biPoolManager.createExchange(pair_cUSD_USDCet);

      // registry.setAddressFor("Broker", address(broker));
      //TODO: Set Oracle report targets for new rates
    }
    vm.stopBroadcast();
  }
}
