// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { Reserve } from "contracts/Reserve.sol";

// forge script script/5-DeployReserve.sol --fork-url http://localhost:8545 --broadcast
contract DeployBroker is Script {
  Reserve reserve;

  function run() public {
    uint256 deployerPkey = vm.envUint("PRIVATE_KEY");
    console2.log("PKey: ", deployerPkey);

    // TODO: pinned version of forge-std doesn't have overload to deploy with privKey
    //       vm.startBroadcast(deployerPkey);
    vm.startBroadcast();
    {
      reserve = new Reserve(true);

      //TODO: Reserve initilisation
    }
    vm.stopBroadcast();

    console2.log("Reserve deployed.");
    console2.log("Deployed at: ", address(reserve));
  }
}
