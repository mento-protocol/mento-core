// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "celo-foundry/Script.sol";
import { ConstantSumPricingModule } from "contracts/ConstantSumPricingModule.sol";

contract DeployConstantSumPricingModule is Script {
  ConstantSumPricingModule pricingModule;

  function run() public {
    uint256 deployer = vm.envUint("ANVIL_PRIVATE_KEY");
    vm.startBroadcast(deployer);
    {
      pricingModule = new ConstantSumPricingModule();
    }
    vm.stopBroadcast();

    console2.log("Constant sum pricing module deployed.");
    console2.log("Deployed at: ", address(pricingModule));
  }
}
