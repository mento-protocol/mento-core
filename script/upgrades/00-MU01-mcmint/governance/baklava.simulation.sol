// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script, console2 } from "forge-std/Script.sol";
import { ScriptHelper } from "script/utils/ScriptHelper.sol";
import { GovernanceHelper } from "script/utils/GovernanceHelper.sol";
import { MentoUpgrade1_baklava_rev0 } from "./baklava.rev0.sol";
import { MentoUpgrade1_baklava_rev1 } from "./baklava.rev1.sol";
import { MentoUpgrade1_baklava_rev2 } from "./baklava.rev2.sol";
import { ICeloGovernance } from "contracts/governance/interfaces/ICeloGovernance.sol";

import { SwapTest } from "script/test/Swap.sol";

// forge script {file} --rpc-url $BAKLAVA_RPC_URL
contract MentoUpgrade1_baklava_simulation is Script, ScriptHelper, GovernanceHelper {
  NetworkProxies private proxies = getNetworkProxies();

  function run() public {
    enableFork();
    // simulate_rev0();
    // simulate_rev1();
    simulate_rev2();
  }

  function simulate_rev0() internal {
    MentoUpgrade1_baklava_rev0 rev0 = new MentoUpgrade1_baklava_rev0();
    simulateProposal(rev0.buildProposal(), proxies.celoGovernance);
  }

  function simulate_rev1() internal {
    MentoUpgrade1_baklava_rev1 rev1 = new MentoUpgrade1_baklava_rev1();
    simulateProposal(rev1.buildProposal(), proxies.celoGovernance);
  }

  function simulate_rev2() internal {
    MentoUpgrade1_baklava_rev2 rev2 = new MentoUpgrade1_baklava_rev2();
    simulateProposal(rev2.buildProposal(), proxies.celoGovernance);
    SwapTest test = new SwapTest();
    test.run();
  }
}
