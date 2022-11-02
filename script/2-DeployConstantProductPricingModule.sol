// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { ConstantProductPricingModule } from "contracts/ConstantProductPricingModule.sol";

// forge script script/2-DeployConstantProductPricingModule.sol --fork-url http://localhost:8545 --broadcast
contract DeployConstantProductPricingModule is Script {
  ConstantProductPricingModule pricingModule;

  function run() public {
    // uint256 deployerPkey = vm.envUint("PRIVATE_KEY");
    // console2.log("PKey: ", deployerPkey);

    // TODO: pinned version of forge-std doesn't have overload to deploy with privKey
    //       vm.startBroadcast(deployerPkey);
    vm.startBroadcast();
    {
      pricingModule = new ConstantProductPricingModule(false);
    }
    vm.stopBroadcast();

    console2.log("Constant product pricing module deployed.");
    console2.log("Deployed at: ", address(pricingModule));
  }
}
