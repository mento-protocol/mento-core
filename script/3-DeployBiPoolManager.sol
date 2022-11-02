// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";

// forge script script/3-DeployBiPoolManager.sol --fork-url http://localhost:8545 --broadcast
contract DeployBiPoolManager is Script {
  BiPoolManager biPoolManager;

  function run() public {
    uint256 deployerPkey = vm.envUint("PRIVATE_KEY");
    console2.log("PKey: ", deployerPkey);

    // TODO: pinned version of forge-std doesn't have overload to deploy with privKey
    //       vm.startBroadcast(deployerPkey);
    vm.startBroadcast();
    {
      biPoolManager = new BiPoolManager(true);
    }
    vm.stopBroadcast();

    console2.log("BiPoolManager deployed.");
    console2.log("Deployed at: ", address(biPoolManager));
  }
}
