// SPDX-License-Identifier: UNLICENSED
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
contract MentoUpgrade1_baklava_rev2 is GovernanceScript {
  ICeloGovernance.Transaction[] private transactions;

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
    address cUSDProxy = contracts.celoRegistry("StableToken");
    address cUSDImpl = contracts.deployed("StableToken");
    address cEURProxy = contracts.celoRegistry("StableTokenEUR");
    address cEURImpl = contracts.deployed("StableTokenEUR");
    address cBRLProxy = contracts.celoRegistry("StableTokenBRL");
    address cBRLImpl = contracts.deployed("StableTokenBRL");

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        cUSDProxy,
        abi.encodeWithSelector(Proxy(0)._setImplementation.selector, cUSDImpl)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        cEURProxy,
        abi.encodeWithSelector(Proxy(0)._setImplementation.selector, cEURImpl)
      )
    );

    transactions.push(
      ICeloGovernance.Transaction(
        0,
        cBRLProxy,
        abi.encodeWithSelector(Proxy(0)._setImplementation.selector, cBRLImpl)
      )
    );
    return transactions;
  }
}