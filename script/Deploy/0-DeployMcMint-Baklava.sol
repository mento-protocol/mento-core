// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "../ScriptHelper.sol";

import { ConstantSumPricingModule } from "contracts/ConstantSumPricingModule.sol";
import { ConstantProductPricingModule } from "contracts/ConstantProductPricingModule.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";
import { Broker } from "contracts/Broker.sol";
import { Reserve } from "contracts/Reserve.sol";
import { StableToken } from "contracts/StableToken.sol";
import { StableTokenBRL } from "contracts/StableTokenBRL.sol";
import { StableTokenEUR } from "contracts/StableTokenEUR.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { BiPoolManagerProxy } from "contracts/proxies/BiPoolManagerProxy.sol";
import { BrokerProxy } from "contracts/proxies/BrokerProxy.sol";

// ANVIL - forge script script/Deploy/0-DeployMcMint.sol --fork-url http://localhost:8545 --broadcast --private-key
// Baklava - forge script script/Deploy/0-DeployMcMint.sol --rpc-url https://baklava-forno.celo-testnet.org --broadcast --legacy

contract DeployMcMint is Script, ScriptHelper {
  ConstantSumPricingModule csPricingModule;
  ConstantProductPricingModule cpPricingModule;
  BiPoolManager biPoolManager;
  Broker broker;
  Reserve reserve;
  StableToken stableToken;
  StableTokenBRL stableTokenBRL;
  StableTokenEUR stableTokenEUR;

  BrokerProxy brokerProxy;
  BiPoolManagerProxy biPoolManagerProxy;

  function run() public {
    NetworkProxies memory proxies = getNetworkProxies(vm.envUint("DEPLOY_NETWORK"));

    vm.startBroadcast();
    {
      // Deploy pricing modules
      csPricingModule = new ConstantSumPricingModule();
      cpPricingModule = new ConstantProductPricingModule();

      // Deploy biPool manager
      biPoolManager = new BiPoolManager(true);
      biPoolManagerProxy = new BiPoolManagerProxy();
      biPoolManagerProxy._setImplementation(address(biPoolManager));
      biPoolManagerProxy._transferOwnership(proxies.celoGovernance);
      biPoolManager.transferOwnership(proxies.celoGovernance);

      // Deploy broker
      broker = new Broker(true);
      brokerProxy = new BrokerProxy();
      brokerProxy._setImplementation(address(broker));
      brokerProxy._transferOwnership(proxies.celoGovernance);
      broker.transferOwnership(proxies.celoGovernance);

      // Deploy reserve
      reserve = new Reserve(true);

      // Deploy stableToken
      stableToken = new StableToken(true);
      stableTokenBRL = new StableTokenBRL(true);
      stableTokenEUR = new StableTokenEUR(true);

      // Init biPoolManager
      BiPoolManager(address(biPoolManagerProxy)).initialize(
        address(brokerProxy),
        IReserve(proxies.reserve),
        ISortedOracles(proxies.sortedOracles)
      );

      address[] memory exchangeProviders = new address[](1);
      exchangeProviders[0] = address(biPoolManagerProxy);

      // Init broker
      Broker(address(brokerProxy)).initialize(exchangeProviders, address(proxies.reserve));
    }
    vm.stopBroadcast();

    console2.log("Constant sum pricing module deployed at: ", address(csPricingModule));
    console2.log("Constant product pricing module deployed at: ", address(cpPricingModule));
    console2.log("----------");
    console2.log("BiPoolManager deployed at: ", address(biPoolManager));
    console2.log("BiPoolManager proxy deployed at: ", address(biPoolManagerProxy));
    console2.log("Set BiPoolManager proxy implementation to ", address(biPoolManager));
    console2.log("Transferred BiPoolManager proxy & implementation ownweship to ", address(proxies.celoGovernance));
    console2.log("----------");
    console2.log("Broker deployed at: ", address(broker));
    console2.log("Broker proxy deployed at: ", address(brokerProxy));
    console2.log("Set Broker proxy implementation to: ", address(brokerProxy));
    console2.log("Transferred Broker proxy & implementation ownweship to ", address(proxies.celoGovernance));
    console2.log("----------");
    console2.log("Reserve deployed at: ", address(reserve));
    console2.log("----------");
    console2.log("StableToken deployed at: ", address(stableToken));
    console2.log("StableTokenBRL deployed at: ", address(stableTokenBRL));
    console2.log("StableTokenEUR deployed at: ", address(stableTokenEUR));
  }
}