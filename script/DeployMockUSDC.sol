// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Script.sol";

import { MockUSDC } from "contracts/goodDollar/mocks/MockUSDC.sol";
contract DeployMockUSDC is Script {
  uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
  address signer = vm.addr(deployerPrivateKey);
  string env = vm.envString("ENV");

  function run() public {
    vm.startBroadcast(deployerPrivateKey);
    MockUSDC mockUSDC = new MockUSDC{ salt: keccak256(abi.encodePacked("MockUSDC", env)) }();

    vm.stopBroadcast();
    console.log("MockUSDC deployed to:", address(mockUSDC));
  }
}
