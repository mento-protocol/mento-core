// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { GovernanceScript } from "script/utils/Script.sol";
import { Chain } from "script/utils/Chain.sol";
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
contract MentoUpgrade1_baklava_rev1 is GovernanceScript {
  ICeloGovernance.Transaction[] private transactions;

  function run() public {
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
    address biPoolManagerProxy = contracts.deployed("BiPoolManagerProxy");
    IBiPoolManager biPoolManager = IBiPoolManager(biPoolManagerProxy);
    bytes32[] memory exchangeIds = biPoolManager.getExchangeIds();
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        biPoolManagerProxy,
        abi.encodeWithSelector(biPoolManager.destroyExchange.selector, exchangeIds[1], 1)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        biPoolManagerProxy,
        abi.encodeWithSelector(biPoolManager.destroyExchange.selector, exchangeIds[0], 0)
      )
    );

    IBiPoolManager.PoolExchange[] memory pools = new IBiPoolManager.PoolExchange[](4);

    address cUSD = contracts.celoRegistry("StableToken");
    address cEUR = contracts.celoRegistry("StableTokenEUR");
    // address cBRL = contracts.celoRegistry("StableTokenBRL");
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
        stablePoolResetSize: 1e24
      })
    });

    pools[1] = IBiPoolManager.PoolExchange({ // cEUR/CELO
      asset0: cUSD,
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
        stablePoolResetSize: 1e24
      })
    });

    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i].asset0 != address(0)) {
        transactions.push(
          ICeloGovernance.Transaction(
            0,
            biPoolManagerProxy,
            abi.encodeWithSelector(biPoolManager.createExchange.selector, pools[i])
          )
        );
      }
    }

    return transactions;
  }
}
