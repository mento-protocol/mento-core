// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;

import { Test } from "forge-std-next/Test.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { Factory } from "./Factory.sol";

interface IRegistryInit {
  function initialize() external;
}

contract BaseTest is Test {
  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  // solhint-disable-next-line const-name-snakecase
  address public constant deployer = address(0x31337);
  Factory public factory;

  constructor() {
    address _factory = address(new Factory());
    vm.etch(deployer, _factory.code);
    factory = Factory(deployer);
    factory.createAt("Registry", REGISTRY_ADDRESS, abi.encode(true));
    vm.prank(deployer);
    IRegistryInit(REGISTRY_ADDRESS).initialize();

    // Deploy required libraries so that vm.getCode will automatically link
    factory.createFromPath(
      "contracts/common/linkedlists/AddressSortedLinkedListWithMedian.sol:AddressSortedLinkedListWithMedian",
      abi.encodePacked()
    );
  }
}
