// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { McMintProposal } from "./CGP-00X-McMint.sol";
import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";

// Baklava
// forge script script/governance/CGP-00X-McMint.sol --rpc-url https://baklava-forno.celo-testnet.org --broadcast --legacy --private-key
contract McMintProposalSimulation is McMintProposal {
  NetworkProxies private proxies = getNetworkProxies();

  function run() public {
    enableFork();
    ICeloGovernance.Transaction[] memory _transactions = buildProposal();
    simulateProposal(_transactions, proxies.celoGovernance);
  }
}
