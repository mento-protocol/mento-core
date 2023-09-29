// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { TestSetup } from "../TestSetup.sol";
import { LibBrokenLine } from "contracts/governance/locking/libs/LibBrokenLine.sol";

contract LibBrokenLine_Test is TestSetup {
  LibBrokenLine.BrokenLine public brokenLine;

  function setUp() public {}

  function assertLineEq(LibBrokenLine.Line memory a, LibBrokenLine.Line memory b) internal {
    assertEq(a.start, b.start);
    assertEq(a.bias, b.bias);
    assertEq(a.slope, b.slope);
    assertEq(a.cliff, b.cliff);
  }

  function blockNumber() internal view returns (uint32) {
    return uint32(block.number);
  }
}
