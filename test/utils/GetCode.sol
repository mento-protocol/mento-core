// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity >=0.5.17 <0.8.19;

library GetCode {
  function at(address _addr) public view returns (bytes memory o_code) {
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
