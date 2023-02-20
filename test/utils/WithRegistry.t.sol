// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.5.13;

import { Test } from "celo-foundry/Test.sol";

import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { Registry } from "contracts/common/Registry.sol";

import { GetCode } from "./GetCode.sol";

contract WithRegistry is Test {
  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  constructor() public {
    vm.etch(REGISTRY_ADDRESS, GetCode.at(address(new Registry(true))));
    vm.label(REGISTRY_ADDRESS, "Registry");
    vm.prank(actor("deployer"));
    Registry(REGISTRY_ADDRESS).initialize();
  }
}
