// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

// import { Test } from "forge-std/Test.sol";
// import { BaseForkTest } from "../BaseForkTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { TestBase } from "forge-std/Base.sol";

import { ExchangeForkTest } from "../ExchangeForkTest.sol";
import { Vm } from "forge-std/Vm.sol";
import { VM_ADDRESS } from "mento-std/Constants.sol";

import { IBroker } from "contracts/interfaces/IBroker.sol";

abstract contract BaseActions is StdCheats {
  Vm internal _vm = Vm(VM_ADDRESS);
  ExchangeForkTest internal ctx = ExchangeForkTest(address(this));
}
