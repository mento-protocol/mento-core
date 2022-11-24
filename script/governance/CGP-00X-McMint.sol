// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "../utils/ScriptHelper.sol";
import { GovernanceHelper } from "../utils/GovernanceHelper.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { IReserve } from "contracts/interfaces/IReserve.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { Proxy } from "contracts/common/Proxy.sol";

// Baklava
// forge script script/governance/CGP-00X-McMint.sol --rpc-url https://baklava-forno.celo-testnet.org --broadcast --legacy --private-key
contract McMintProposal is Script, ScriptHelper, GovernanceHelper {
  using FixidityLib for FixidityLib.Fraction;

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
        proxies.reserve,
        abi.encodeWithSelector(Proxy(0)._setImplementation.selector, implementations.reserve)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.stableToken,
        abi.encodeWithSelector(Proxy(0)._setImplementation.selector, implementations.stableToken)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.stableTokenEUR,
        abi.encodeWithSelector(Proxy(0)._setImplementation.selector, implementations.stableTokenEUR)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.stableTokenBRL,
        abi.encodeWithSelector(Proxy(0)._setImplementation.selector, implementations.stableTokenBRL)
      )
    );
  }

  function proposal_configureReserve() private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.reserve,
        abi.encodeWithSelector(IReserve(0).addExchangeSpender.selector, proxies.broker)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.reserve,
        abi.encodeWithSelector(IReserve(0).addCollateralAsset.selector, implementations.usdcToken)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.reserve,
        abi.encodeWithSelector(IReserve(0).addCollateralAsset.selector, proxies.celoToken)
      )
    );
  }

  function proposal_registryUpdates() private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.registry,
        abi.encodeWithSelector(IRegistry(0).setAddressFor.selector, "Broker", proxies.broker)
      )
    );
  }

  function proposal_createExchanges() private {
    // TODO: confirm values
    // Add pools to the BiPoolManager: cUSD/CELO, cEUR/CELO, cREAL/CELO, cUSD/USDCet

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
        stablePoolResetSize: 24
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
            proxies.biPoolManager,
            abi.encodeWithSelector(IBiPoolManager(0).createExchange.selector, pools[i])
          )
        );
      }
    }
  }
}
