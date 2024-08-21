// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { IOwnable } from "contracts/interfaces/IOwnable.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { VM_ADDRESS } from "mento-std/Constants.sol";

library Fixtures {
  Vm internal constant vm = Vm(VM_ADDRESS);
  // Address of the AddressSortedLinkedListWithMedian library as
  // linked in the SortedOracles binary fixture.
  // If the fixture is regenerated, this address must be updated.
  address constant ASLLWMAddress = 0x694167c0c678b13fD1ED94DD1ddCe20464D66653;

  function sortedOracles() internal returns (address) {
    initAt("AddressSortedLinkedListWithMedian", ASLLWMAddress);
    address _sortedOracles = init("SortedOracles");

    address owner = IOwnable(_sortedOracles).owner();
    vm.prank(owner);
    IOwnable(_sortedOracles).transferOwnership(address(this));
    return _sortedOracles;
  }

  function init(string memory fixture) internal returns (address) {
    return init(fixture, keccak256(abi.encodePacked(fixture)));
  }

  function init(string memory fixture, string memory salt) internal returns (address) {
    return init(fixture, keccak256(abi.encodePacked(fixture, salt)));
  }

  function initAt(string memory fixture, address at) internal returns (address) {
    bytes memory code = vm.readFileBinary(string(abi.encodePacked("./test-v2/fixtures/", fixture, ".bin")));
    vm.etch(at, code);
    vm.label(at, fixture);
    return at;
  }

  function init(string memory fixture, bytes32 key) internal returns (address) {
    return initAt(fixture, vm.addr(uint256(key)));
  }
}
