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
contract MentoUpgrade1_baklava_rev2 is Script, ScriptHelper, GovernanceHelper {
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
    return transactions;
  }
}