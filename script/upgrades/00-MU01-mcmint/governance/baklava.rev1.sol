// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "script/utils/ScriptHelper.sol";
import { GovernanceHelper } from "script/utils/GovernanceHelper.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { Proxy } from "contracts/common/Proxy.sol";


/**
 forge script {file} --rpc-url $BAKLAVA_RPC_URL 
                     --broadcast --legacy 
                     --private-key $BAKLAVA_MENTO_PROPOSER
 * @dev Initial CGP (./baklava.sol) had a mistake in the bucket sizes.
 */
contract MentoUpgrade1_baklava_rev1 is Script, ScriptHelper, GovernanceHelper {
  ICeloGovernance.Transaction[] private transactions;
  NetworkProxies private proxies = getNetworkProxies();
  NetworkImplementations private implementations = getNetworkImplementations();

  function run() public {
    ICeloGovernance.Transaction[] memory _transactions = buildProposal();

    vm.startBroadcast();
    {
      createProposal(_transactions, "TODO", proxies.celoGovernance);
    }
    vm.stopBroadcast();
  }

  function buildProposal() public returns (ICeloGovernance.Transaction[] memory) {
    IBiPoolManager biPoolManager = IBiPoolManager(proxies.biPoolManager);
    bytes32[] memory exchangeIds = biPoolManager.getExchangeIds();
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.biPoolManager,
        abi.encodeWithSelector(
          IBiPoolManager(0).destroyExchange.selector, 
          exchangeIds[1], 
          1
        )
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.biPoolManager,
        abi.encodeWithSelector(
          IBiPoolManager(0).destroyExchange.selector, 
          exchangeIds[0], 
          0
        )
      )
    );

    IBiPoolManager.PoolExchange[] memory pools = new IBiPoolManager.PoolExchange[](4);

    pools[0] = IBiPoolManager.PoolExchange({ // cUSD/CELO
      asset0: proxies.stableToken,
      asset1: proxies.celoToken,
      pricingModule: IPricingModule(implementations.constantProductPricingModule),
      bucket0: 0,
      bucket1: 0,
      lastBucketUpdate: 0,
      config: IBiPoolManager.PoolConfig({
        spread: FixidityLib.newFixedFraction(5, 100),
        referenceRateFeedID: proxies.stableToken,
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 1e24
      })
    });

    pools[1] = IBiPoolManager.PoolExchange({ // cEUR/CELO
      asset0: proxies.stableTokenEUR,
      asset1: proxies.celoToken,
      pricingModule: IPricingModule(implementations.constantProductPricingModule),
      bucket0: 0,
      bucket1: 0,
      lastBucketUpdate: 0,
      config: IBiPoolManager.PoolConfig({
        spread: FixidityLib.newFixedFraction(5, 100),
        referenceRateFeedID: proxies.stableTokenEUR,
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 1e24
      })
    });

    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i].asset0 != address(0)) {
        transactions.push(
          ICeloGovernance.Transaction(
            0,
            proxies.biPoolManager,
            abi.encodeWithSelector(IBiPoolManager(0).createExchange.selector, pools[i])
          )
        );
      }
    }

    return transactions;
  }
}