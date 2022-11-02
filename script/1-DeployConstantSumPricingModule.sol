// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;

import { Script, console2 } from "forge-std/Script.sol";
import { ConstantSumPricingModule } from "contracts/ConstantSumPricingModule.sol";

// ANVIL - forge script script/1-DeployConstantSumPricingModule.sol --fork-url http://localhost:8545 --broadcast
// Baklava - forge script script/1-DeployConstantSumPricingModule.sol --rpc-url https://baklava-forno.celo-testnet.org --broadcast

// TODO: Baklava deploy fails:
//       (code: -32601, message: the method eth_feeHistory does not exist/is not available, data: None)

contract DeployConstantSumPricingModule is Script {
  ConstantSumPricingModule pricingModule;

  function run() public {
    uint256 deployerPkey = vm.envUint("PRIVATE_KEY");
    console2.log("PKey: ", deployerPkey);

    // TODO: pinned version of forge-std doesn't have overload to deploy with privKey
    //       vm.startBroadcast(deployerPkey);
    vm.startBroadcast();
    {
      pricingModule = new ConstantSumPricingModule(false);
    }
    vm.stopBroadcast();

    console2.log("Constant sum pricing module deployed.");
    console2.log("Deployed at: ", address(pricingModule));
  }
}
