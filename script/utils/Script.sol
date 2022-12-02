// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Script as BaseScript, console2 } from "forge-std/Script.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { Chain } from "./Chain.sol";
import { Contracts } from "./Contracts.sol";
import { GovernanceHelper } from "./GovernanceHelper.sol";

contract Script is BaseScript {
  using Contracts for Contracts.Cache;
  using FixidityLib for FixidityLib.Fraction;

  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;

  Contracts.Cache public contracts;
}

contract GovernanceScript is Script, GovernanceHelper {}