// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { MentoUpgrade1_baklava } from "./baklava.sol";
import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";

// forge script {file} --rpc-url $BAKLAVA_RPC_URL
contract MentoUpgrade1_baklava_simulation is MentoUpgrade1_baklava {
  NetworkProxies private proxies = getNetworkProxies();

  function run() public {
    enableFork();
    ICeloGovernance.Transaction[] memory _transactions = buildProposal();
    simulateProposal(_transactions, proxies.celoGovernance);
  }
}
