// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import { Test } from "celo-foundry/Test.sol";

import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { Registry } from "contracts/common/Registry.sol";
import { Factory } from "./Factory.sol";

contract WithRegistry is Test {
  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  constructor() public {
    Factory factory = new Factory();
    factory.createAt("Registry", REGISTRY_ADDRESS, abi.encode(true));
    Registry(REGISTRY_ADDRESS).initialize();
  }
}
