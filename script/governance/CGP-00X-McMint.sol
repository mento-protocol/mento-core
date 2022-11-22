// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "../ScriptHelper.sol";
import { GovernanceHelper } from "../GovernanceHelper.sol";

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

  NetworkProxies private proxies = getNetworkProxies(chainId());
  NetworkImplementations private implementations = getNetworkImplementations(chainId());

  function run() public {
    proposal_upgradeContracts();
    proposal_setBrokerAsReserveSpender();
    proposal_registryUpdates();
    proposal_createExchanges();
    //TODO: Set Oracle report targets for new rates

    vm.startBroadcast();
    {
      // Serialize transactions
      (
        uint256[] memory values,
        address[] memory destinations,
        bytes memory data,
        uint256[] memory dataLengths
      ) = serializeTransactions(transactions);

      uint256 depositAmount = ICeloGovernance(proxies.celoGovernance).minDeposit();
      console2.log("Celo governance proposal required deposit amount: ", depositAmount);

      // Submit proposal
      (bool success, bytes memory returnData) = address(proxies.celoGovernance).call.value(depositAmount)(
        abi.encodeWithSelector(
          ICeloGovernance(0).propose.selector,
          values,
          destinations,
          data,
          dataLengths,
          "CGP-00X-McMint"
        )
      );

      if (success == false) {
        console2.log("Failed to create proposal");
        console2.logBytes(returnData);
      }
      require(success);

      console2.log("Proposal was successfully created. ID: ", abi.decode(returnData, (uint256)));
    }
    vm.stopBroadcast();
  }

  function proposal_upgradeContracts() private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.reserve,
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          implementations.reserve
        )
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.stableToken,
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          implementations.stableToken
        )
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.stableTokenEUR,
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          implementations.stableTokenEUR
        )
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.stableTokenBRL,
        abi.encodeWithSelector(
          Proxy(0)._setImplementation.selector, 
          implementations.stableTokenBRL
        )
      )
    );
  }

  function proposal_setBrokerAsReserveSpender() private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.reserve,
        abi.encodeWithSelector(
          IReserve(0).addExchangeSpender.selector,
          proxies.broker
        )
      )
    );
  }

  function proposal_registryUpdates() private {
    transactions.push(
      ICeloGovernance.Transaction(
        0,
        proxies.registry,
        abi.encodeWithSelector(
          IRegistry(0).setAddressFor.selector,
          "Broker",
          proxies.broker
        )
      )
    );
  }

  function proposal_createExchanges()
    private
  {
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
        oracleReportTarget: proxies.stableToken,
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 24
      })
    });

    pools[1] =  IBiPoolManager.PoolExchange({ // cEUR/CELO
      asset0: proxies.stableTokenEUR,
      asset1: proxies.celoToken,
      pricingModule: IPricingModule(implementations.constantProductPricingModule),
      bucket0: 0,
      bucket1: 0,
      lastBucketUpdate: 0,
      config: IBiPoolManager.PoolConfig({
        spread: FixidityLib.newFixedFraction(5, 100),
        oracleReportTarget: proxies.stableTokenEUR,
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 24
      })
    });

    pools[2] =  IBiPoolManager.PoolExchange({ // cREAL/CELO
      asset0: proxies.stableTokenBRL,
      asset1: proxies.celoToken,
      pricingModule: IPricingModule(implementations.constantProductPricingModule),
      bucket0: 0,
      bucket1: 0,
      lastBucketUpdate: 0,
      config: IBiPoolManager.PoolConfig({
        spread: FixidityLib.newFixedFraction(5, 100),
        oracleReportTarget: proxies.stableTokenBRL,
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 24
      })
    });
    
    pools[3] = IBiPoolManager.PoolExchange({ // cUSD/USDCet
      asset0: proxies.stableToken,
      asset1: implementations.usdcToken,
      pricingModule: IPricingModule(implementations.constantSumPricingModule),
      bucket0: 0,
      bucket1: 0,
      lastBucketUpdate: 0,
      config: IBiPoolManager.PoolConfig({
        spread: FixidityLib.newFixedFraction(5, 100),
        oracleReportTarget: address(bytes20(keccak256(abi.encode("cUSD/USDC")))),
        referenceRateResetFrequency: 60 * 5,
        minimumReports: 5,
        stablePoolResetSize: 24
      })
    });

    for (uint256 i = 0; i < pools.length; i++) {
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
