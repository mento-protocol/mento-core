// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract GetWeek_Locking_Test is Locking_Test {
  uint32 currentBlock = 15691519;
  uint32 epochShift = 39725;

  function _subject() internal returns (uint256) {
    return lockingContract.getWeek();
  }

  function setUp() public override {
    super.setUp();
    _newLocking();
    lockingContract.setEpochShift(epochShift);
    lockingContract.setBlock(currentBlock);
  }

  function test_getWeek_shouldReturnCorrectWeekNo() public {
    assertEq(_subject(), 310);
    assertEq(lockingContract.blockTillNextPeriod(), 22606);

    _incrementBlock(22000);
    assertEq(_subject(), 310);
    _incrementBlock(600);
    assertEq(_subject(), 310);
    _incrementBlock(10);
    assertEq(_subject(), 311);
  }
}
