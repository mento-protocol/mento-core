// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;

import { console } from "forge-std/console.sol";
import { SortedOracles } from "celo/contracts/stability/SortedOracles.sol";

interface Vm {
  function writeFile(string calldata, string calldata) external;

  function writeFileBinary(string calldata path, bytes calldata data) external;
}

contract UpdateSortedOraclesFixture {
  address private constant VM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
  Vm private constant vm = Vm(VM_ADDRESS);

  bool public constant IS_SCRIPT = true;

  function run() public {
    SortedOracles sortedOracles = new SortedOracles(true);
    bytes memory sortedOraclesCode = codeAt(address(sortedOracles));
    vm.writeFileBinary("./test-v2/fixtures/SortedOracles.bin", sortedOraclesCode);
    address libAddress;
    // cat out/SortedOracles.sol/SortedOracles.json | jq '.deployedBytecode.linkReferences'
    // Get the first offset from the output, that's the magic number 2183.
    // If Sorted oracles changes we need to recompute this offset.
    uint256 libraryOffset = 2183 - 12;
    assembly {
      libAddress := mload(add(add(sortedOraclesCode, 0x20), libraryOffset))
    }
    console.log(libAddress);
    bytes memory libCode = codeAt(libAddress);
    vm.writeFileBinary("./test-v2/fixtures/AddressSortedLinkedListWithMedian.bin", libCode);
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
