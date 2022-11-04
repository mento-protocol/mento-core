// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { DeployHelper } from "./DeployHelper.sol";

import { BiPoolManager } from "contracts/BiPoolManager.sol";
import { BiPoolManagerProxy } from "contracts/proxies/BiPoolManagerProxy.sol";

// forge script script/3-DeployBiPoolManager.sol --fork-url http://localhost:8545 --broadcast
contract DeployBiPoolManager is Script, DeployHelper {
  BiPoolManager biPoolManager;
  BiPoolManagerProxy biPoolManagerProxy;

  function run() public {
    uint256 deployerPkey = vm.envUint("PRIVATE_KEY");
    console2.log("PKey: ", deployerPkey);

    MentoConfig memory config = getAnvilConfig();

    // TODO: pinned version of forge-std doesn't have overload to deploy with privKey
    //       vm.startBroadcast(deployerPkey);
    vm.startBroadcast();
    {
      biPoolManager = new BiPoolManager(true);
      console2.log("BiPoolManager deployed.");
      console2.log("BiPoolManager deployed at: ", address(biPoolManager));

      biPoolManagerProxy = new BiPoolManagerProxy();
      console2.log("BiPoolManager proxy deployed.");
      console2.log("BiPoolManager proxy deployed at: ", address(biPoolManagerProxy));

      biPoolManagerProxy._setImplementation(address(biPoolManager));

      biPoolManagerProxy._transferOwnership(config.governance);
      biPoolManager.transferOwnership(config.governance);
    }
    vm.stopBroadcast();
  }
}
