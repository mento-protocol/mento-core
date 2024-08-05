// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17 <0.8.19;

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
  MiniVM internal constant VM = MiniVM(VM_ADDRESS);

  function createFromPath(string memory _path, bytes memory args) public returns (address) {
    bytes memory bytecode = abi.encodePacked(VM.getCode(_path), args);
    address addr;

    // solhint-disable-next-line no-inline-assembly
    assembly {
      addr := create(0, add(bytecode, 0x20), mload(bytecode))
    }
    return addr;
  }

  function createContract(string memory _contract, bytes memory args) public returns (address addr) {
    string memory path = contractPath(_contract);
    addr = createFromPath(path, args);
    console.log("Deployed %s to %s", _contract, addr);
    return addr;
  }

  function contractPath(string memory _contract) public pure returns (string memory) {
    return string(abi.encodePacked("out/", _contract, ".sol", "/", _contract, ".json"));
  }

  function createAt(
    string memory _contract,
    address dest,
    bytes memory args
  ) public {
    address addr = createContract(_contract, args);
    VM.etch(dest, GetCode.at(addr));
    console.log("Etched %s to %s", _contract, dest);
  }
}
