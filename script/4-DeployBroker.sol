// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { Broker } from "contracts/Broker.sol";

// forge script script/4-DeployBroker.sol --fork-url http://localhost:8545 --broadcast
contract DeployBroker is Script {
  Broker broker;

  function run() public {
    uint256 deployerPkey = vm.envUint("PRIVATE_KEY");
    console2.log("PKey: ", deployerPkey);

    // TODO: pinned version of forge-std doesn't have overload to deploy with privKey
    //       vm.startBroadcast(deployerPkey);
    vm.startBroadcast();
    {
      broker = new Broker(true);
    }
    vm.stopBroadcast();

    console2.log("Broker deployed.");
    console2.log("Deployed at: ", address(broker));
  }
}
