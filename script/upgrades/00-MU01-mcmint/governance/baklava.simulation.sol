// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { GovernanceScript } from "script/utils/Script.sol";
import { console2 } from "forge-std/Script.sol";
import { MentoUpgrade1_baklava_rev0 } from "./baklava.rev0.sol";
import { MentoUpgrade1_baklava_rev1 } from "./baklava.rev1.sol";
import { MentoUpgrade1_baklava_rev2 } from "./baklava.rev2.sol";
import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";

import { SwapTest } from "script/test/Swap.sol";
import { Chain } from "script/utils/Chain.sol";

// forge script {file} --rpc-url $BAKLAVA_RPC_URL
contract MentoUpgrade1_baklava_simulation is GovernanceScript {
  address public governance;

  function run() public {
    Chain.fork();
    governance = contracts.celoRegistry("Governance");
    // simulate_rev0();
    // simulate_rev1();
    simulate_rev2();
  }

  function simulate_rev0() internal {
    MentoUpgrade1_baklava_rev0 rev0 = new MentoUpgrade1_baklava_rev0();
    simulateProposal(rev0.buildProposal(), governance);
  }

  function simulate_rev1() internal {
    MentoUpgrade1_baklava_rev1 rev1 = new MentoUpgrade1_baklava_rev1();
    simulateProposal(rev1.buildProposal(), governance);
  }

  function simulate_rev2() internal {
    MentoUpgrade1_baklava_rev2 rev2 = new MentoUpgrade1_baklava_rev2();
    simulateProposal(rev2.buildProposal(), governance);
    SwapTest test = new SwapTest();
    test.run();
  }
}
