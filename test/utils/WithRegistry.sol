// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { CVS } from "mento-std/CVS.sol";
import { CELO_REGISTRY_ADDRESS } from "mento-std/Constants.sol";

import { IRegistry } from "celo/contracts/common/interfaces/IRegistry.sol";

interface IRegistryInit {
  function initialize() external;
}

contract WithRegistry {
  IRegistry public registry = IRegistry(CELO_REGISTRY_ADDRESS);

  constructor() {
    CVS.deployTo(CELO_REGISTRY_ADDRESS, "Registry", abi.encode(true));
    IRegistryInit(CELO_REGISTRY_ADDRESS).initialize();
  }
}
