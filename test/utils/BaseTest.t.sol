// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import { Test } from "celo-foundry/Test.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { Registry } from "contracts/common/Registry.sol";
import { Factory } from "./Factory.sol";
import { GetCode } from "./GetCode.sol";

contract BaseTest is Test {
  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  address public constant DEPLOYER = address(0x31337);
  Factory public factory;

  constructor() public {
    address _factory = address(new Factory());
    vm.etch(DEPLOYER, GetCode.at(_factory));
    factory = Factory(DEPLOYER);
    factory.createAt("Registry", REGISTRY_ADDRESS, abi.encode(true));
    vm.prank(DEPLOYER);
    Registry(REGISTRY_ADDRESS).initialize();
  }
}
