// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { DeployHelper } from "./DeployHelper.sol";

import { Broker } from "contracts/Broker.sol";
import { BrokerProxy } from "contracts/proxies/BrokerProxy.sol";

// forge script script/4-DeployBroker.sol --fork-url http://localhost:8545 --broadcast
contract DeployBroker is Script, DeployHelper {
  Broker broker;
  BrokerProxy brokerProxy;

  function run() public {
    uint256 deployerPkey = vm.envUint("PRIVATE_KEY");
    console2.log("PKey: ", deployerPkey);

    MentoConfig memory config = getAnvilConfig();

    // TODO: pinned version of forge-std doesn't have overload to deploy with privKey
    //       vm.startBroadcast(deployerPkey);
    vm.startBroadcast();
    {
      broker = new Broker(true);
      console2.log("Broker deployed.");
      console2.log("Broker deployed at: ", address(broker));

      brokerProxy = new BrokerProxy();
      console2.log("Broker proxy deployed.");
      console2.log("Broker proxy deployed at: ", address(brokerProxy));

      brokerProxy._setImplementation(address(broker));

      brokerProxy._transferOwnership(config.governance);
      broker.transferOwnership(config.governance);

      // TODO: Contract verification
    }
    vm.stopBroadcast();
  }
}
