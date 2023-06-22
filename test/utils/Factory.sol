// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17 <0.9.0;

import { console } from "forge-std/console.sol";
import { GetCode } from "./GetCode.sol";

interface MiniVM {
  function etch(address _addr, bytes calldata _code) external;

  function getCode(string calldata _path) external view returns (bytes memory);
}

/**
 * @title Factory
 * @dev Should be use to allow interoperability between solidity versions.
 *      Contracts with a newer solidity version should be initialized through this contract.
 *      See initilization of StableToken in Exchange.t.sol setup() for an example.
 */
contract Factory {
  address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
  MiniVM internal constant vm = MiniVM(VM_ADDRESS);

  function createFromPath(string memory _path, bytes memory args) public returns (address) {
    bytes memory bytecode = abi.encodePacked(vm.getCode(_path), args);
    address addr;

    assembly {
      addr := create(0, add(bytecode, 0x20), mload(bytecode))
    }
    return addr;
  }

  function create(string memory _contract, bytes memory args) public returns (address addr) {
    string memory path = string(abi.encodePacked("out/", _contract, ".sol", "/", _contract, ".json"));
    addr = createFromPath(path, args);
    console.log("Deployed %s to %s", _contract, addr);
    return addr;
  }

  function createAt(
    string memory _contract,
    address dest,
    bytes memory args
  ) public {
    address addr = create(_contract, args);
    vm.etch(dest, GetCode.at(addr));
    console.log("Etched %s to %s", _contract, dest);
  }
}
