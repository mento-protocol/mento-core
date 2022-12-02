// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { GovernanceScript } from "script/utils/Script.sol";
import { console2 } from "forge-std/Script.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { Proxy } from "contracts/common/Proxy.sol";
import { Contracts } from "script/utils/Contracts.sol";
import { Chain } from "script/utils/Chain.sol";

/**
 forge script {file} --rpc-url $BAKLAVA_RPC_URL 
                     --broadcast --legacy 
 * @dev depends on deploy/00-CircuitBreaker.sol and deploy/01-Broker.sol
 */
contract MentoUpgrade1_baklava_rev0 is GovernanceScript {
  ICeloGovernance.Transaction[] private transactions;

  // NetworkProxies private proxies = getNetworkProxies();
  // NetworkImplementations private implementations = getNetworkImplementations();

  function run() public {
    contracts.load("00-CircuitBreaker", "1669916685");
    contracts.load("01-Broker", "1669916825");
    address governance = contracts.celoRegistry("Governance");
    ICeloGovernance.Transaction[] memory _transactions = buildProposal();

    vm.startBroadcast(Chain.deployerPrivateKey());
    {
      createProposal(_transactions, "TODO", governance);
    }
    vm.stopBroadcast();
  }

  function buildProposal() public returns (ICeloGovernance.Transaction[] memory) {
    require(transactions.length == 0);
    proposal_upgradeContracts();
    proposal_configureReserve();
    proposal_registryUpdates();
    proposal_createExchanges();
    //TODO: Set Oracle report targets for new rates
    return transactions;
  }

  function proposal_upgradeContracts() private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        contracts.celoRegistry("Reserve"),
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          contracts.deployed("Reserve")
        )
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        contracts.celoRegistry("StableToken"),
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          contracts.deployed("StableToken")
        )
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        contracts.celoRegistry("StableTokenEUR"),
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          contracts.deployed("StableTokenEUR")
        )
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        contracts.celoRegistry("StableTokenBRL"),
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          contracts.deployed("StableTokenBRL")
        )
      )
    );
  }

  function proposal_configureReserve() private {
    address reserveProxy = contracts.celoRegistry("Reserve");
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        reserveProxy,
        abi.encodeWithSelector(IReserve(0).addExchangeSpender.selector, contracts.deployed("BrokerProxy"))
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        reserveProxy,
        abi.encodeWithSelector(IReserve(0).addCollateralAsset.selector, contracts.dependency("USDCet"))
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        reserveProxy,
        abi.encodeWithSelector(IReserve(0).addCollateralAsset.selector, contracts.celoRegistry("GoldToken"))
      )
    );
  }

  function proposal_registryUpdates() private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        REGISTRY_ADDRESS,
        abi.encodeWithSelector(IRegistry(0).setAddressFor.selector, "Broker", contracts.deployed("BrokerProxy"))
      )
    );
  }

  function proposal_createExchanges() private {
    // TODO: confirm values
    // Add pools to the BiPoolManager: cUSD/CELO, cEUR/CELO, cREAL/CELO, cUSD/USDCet

    IBiPoolManager.PoolExchange[] memory pools = new IBiPoolManager.PoolExchange[](4);

    address cUSD = contracts.celoRegistry("StableToken");
    address cEUR = contracts.celoRegistry("StableTokenEUR");
    address cBRL = contracts.celoRegistry("StableTokenBRL");
    address celo = contracts.celoRegistry("GoldToken");
    IPricingModule constantProduct = IPricingModule(contracts.deployed("ConstantProductPricingModule"));

    pools[0] = IBiPoolManager.PoolExchange({ // cUSD/CELO
      asset0: cUSD,
      asset1: celo,
      pricingModule: constantProduct,
      bucket0: 0,
      bucket1: 0,
      lastBucketUpdate: 0,
      config: IBiPoolManager.PoolConfig({
        spread: FixidityLib.newFixedFraction(5, 100),
        referenceRateFeedID: cUSD,
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 24
      })
    });

    pools[1] = IBiPoolManager.PoolExchange({ // cEUR/CELO
      asset0: cEUR,
      asset1: celo,
      pricingModule: constantProduct,
      bucket0: 0,
      bucket1: 0,
      lastBucketUpdate: 0,
      config: IBiPoolManager.PoolConfig({
        spread: FixidityLib.newFixedFraction(5, 100),
        referenceRateFeedID: cEUR,
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 24
      })
    });

    // XXX: Commented because cREAL isn't deployed to baklava :(
    // pools[2] =  IBiPoolManager.PoolExchange({ // cREAL/CELO
    //   asset0: proxies.stableTokenBRL,
    //   asset1: proxies.celoToken,
    //   pricingModule: IPricingModule(implementations.constantProductPricingModule),
    //   bucket0: 0,
    //   bucket1: 0,
    //   lastBucketUpdate: 0,
    //   config: IBiPoolManager.PoolConfig({
    //     spread: FixidityLib.newFixedFraction(5, 100),
    //     referenceRateFeedID: proxies.stableTokenBRL,
    //     referenceRateResetFrequency: 60 * 5,
    //     minimumReports: 5,
    //     stablePoolResetSize: 24
    //   })
    // });

    // XXX: Commented because I'm not sure USDCet is on baklava
    // pools[3] = IBiPoolManager.PoolExchange({ // cUSD/USDCet
    //   asset0: proxies.stableToken,
    //   asset1: implementations.usdcToken,
    //   pricingModule: IPricingModule(implementations.constantSumPricingModule),
    //   bucket0: 0,
    //   bucket1: 0,
    //   lastBucketUpdate: 0,
    //   config: IBiPoolManager.PoolConfig({
    //     spread: FixidityLib.newFixedFraction(5, 100),
    //     referenceRateFeedID: address(bytes20(keccak256(abi.encode("cUSD/USDC")))),
    //     referenceRateResetFrequency: 60 * 5,
    //     minimumReports: 5,
    //     stablePoolResetSize: 24
    //   })
    // });

    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i].asset0 != address(0)) {
        transactions.push(
          ICeloGovernance.Transaction(
            0,
            contracts.deployed("BiPoolManagerProxy"),
            abi.encodeWithSelector(IBiPoolManager(0).createExchange.selector, pools[i])
          )
        );
      }
    }
  }
}
