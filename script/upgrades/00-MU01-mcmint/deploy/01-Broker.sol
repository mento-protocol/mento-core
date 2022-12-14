// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script } from "script/utils/Script.sol";
import { Chain } from "script/utils/Chain.sol";
import { console2 } from "forge-std/Script.sol";

import { ConstantSumPricingModule } from "contracts/ConstantSumPricingModule.sol";
import { ConstantProductPricingModule } from "contracts/ConstantProductPricingModule.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";
import { Broker } from "contracts/Broker.sol";
import { Reserve } from "contracts/Reserve.sol";
import { StableToken } from "contracts/StableToken.sol";
import { StableTokenBRL } from "contracts/StableTokenBRL.sol";
import { StableTokenEUR } from "contracts/StableTokenEUR.sol";

import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { BiPoolManagerProxy } from "contracts/proxies/BiPoolManagerProxy.sol";
import { BrokerProxy } from "contracts/proxies/BrokerProxy.sol";
import { ReserveProxy } from "contracts/proxies/ReserveProxy.sol";

/*
 Baklava: 
 forge script {file} --rpc-url $BAKLAVA_RPC_URL 
                     --broadcast --legacy --verify --verifier sourcify 
                     --private-key $BAKLAVA_DEPLOYER_PK
*/

contract DeployBrokerScript is Script {
  ConstantSumPricingModule private csPricingModule;
  ConstantProductPricingModule private cpPricingModule;
  BiPoolManager private biPoolManager;
  Broker private broker;
  Reserve private reserve;
  StableToken private stableToken;
  StableTokenBRL private stableTokenBRL;
  StableTokenEUR private stableTokenEUR;

  BrokerProxy private brokerProxy;
  BiPoolManagerProxy private biPoolManagerProxy;

  function run() public {
    // Existing proxies
    address governance = contracts.celoRegistry("Governance");
    address reserveProxy = contracts.celoRegistry("Reserve");
    address sortedOraclesProxy = contracts.celoRegistry("SortedOracles");
    contracts.load("00-CircuitBreaker", "1669916685");
    address breakerBoxProxy = contracts.deployed("BreakerBoxProxy");

    vm.startBroadcast(Chain.deployerPrivateKey());
    {
      // Deploy updated implementations
      reserve = new Reserve(false);
      stableToken = new StableToken(false);
      stableTokenBRL = new StableTokenBRL(false);
      stableTokenEUR = new StableTokenEUR(false);

      // Deploy stateless contracts
      csPricingModule = new ConstantSumPricingModule();
      cpPricingModule = new ConstantProductPricingModule();

      // Deploy new proxies
      biPoolManagerProxy = new BiPoolManagerProxy();
      brokerProxy = new BrokerProxy();

      // Deploy & Initialize BiPoolManager
      biPoolManager = new BiPoolManager(false);

      biPoolManagerProxy._setAndInitializeImplementation(
        address(biPoolManager),
        abi.encodeWithSelector(
          BiPoolManager(0).initialize.selector,
          address(brokerProxy),
          IReserve(reserveProxy),
          ISortedOracles(sortedOraclesProxy),
          IBreakerBox(breakerBoxProxy)
        )
      );
      biPoolManagerProxy._transferOwnership(governance);
      BiPoolManager(address(biPoolManagerProxy)).transferOwnership(governance);

      // Deploy & Initialize Broker
      broker = new Broker(false);

      address[] memory exchangeProviders = new address[](1);
      exchangeProviders[0] = address(biPoolManagerProxy);

      brokerProxy._setAndInitializeImplementation(
        address(broker),
        abi.encodeWithSelector(Broker(0).initialize.selector, exchangeProviders, reserveProxy)
      );
      brokerProxy._transferOwnership(governance);
      Broker(address(brokerProxy)).transferOwnership(governance);
    }
    vm.stopBroadcast();

    console2.log("Constant sum pricing module deployed at: ", address(csPricingModule));
    console2.log("Constant product pricing module deployed at: ", address(cpPricingModule));
    console2.log("----------");
    console2.log("BiPoolManager deployed at: ", address(biPoolManager));
    console2.log("BiPoolManager proxy deployed at: ", address(biPoolManagerProxy));
    console2.log("Set BiPoolManager proxy implementation to ", address(biPoolManager));
    console2.log("Transferred BiPoolManager proxy & implementation ownweship to ", address(governance));
    console2.log("----------");
    console2.log("Broker deployed at: ", address(broker));
    console2.log("Broker proxy deployed at: ", address(brokerProxy));
    console2.log("Set Broker proxy implementation to: ", address(brokerProxy));
    console2.log("Transferred Broker proxy & implementation ownweship to ", address(governance));
    console2.log("----------");
    console2.log("Reserve deployed at: ", address(reserve));
    console2.log("----------");
    console2.log("StableToken deployed at: ", address(stableToken));
    console2.log("StableTokenBRL deployed at: ", address(stableTokenBRL));
    console2.log("StableTokenEUR deployed at: ", address(stableTokenEUR));
  }
}
