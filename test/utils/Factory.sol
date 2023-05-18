// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.17 <0.9.0;

import { console } from "forge-std/console.sol";

interface MiniVM {
  function etch(address _addr, bytes calldata _code) external;
  function getCode(string calldata _path) external view returns (bytes memory);
  function startPrank(address _prankster) external;
  function stopPrank() external;
}

contract Factory {
  address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
  address public constant deployer = address(0x31337);
  MiniVM internal constant vm = MiniVM(VM_ADDRESS);

  function createFromPath(string memory _path, bytes memory args) public returns (address) {
    bytes memory bytecode = abi.encodePacked(vm.getCode(_path), args);
    address addr;
    vm.stopPrank();
    vm.startPrank(deployer);
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

  function createAt(string memory _contract, address dest, bytes memory args) public {
    address addr = create(_contract, args);
    vm.etch(dest, codeAt(addr));
    console.log("Etched %s to %s",_contract, dest);
  }

  function codeAt(address _addr) internal view returns (bytes memory o_code) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      // retrieve the size of the code
      let size := extcodesize(_addr)
      // allocate output byte array
      // by using o_code = new bytes(size)
      o_code := mload(0x40)
      // new "memory end" including padding
      mstore(0x40, add(o_code, and(add(add(size, 0x20), 0x1f), not(0x1f))))
      // store length in memory
      mstore(o_code, size)
      // actually retrieve the code, this needs assembly
      extcodecopy(_addr, add(o_code, 0x20), 0, size)
    }
  }
}
