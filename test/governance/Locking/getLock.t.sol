// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract GetLock_Locking_Test is Locking_Test {
  uint96 public amount;
  uint32 public slopePeriod;
  uint32 public cliff;

  function _subject() internal returns (uint96, uint96) {
    return lockingContract.getLock(amount, slopePeriod, cliff);
  }

  function setUp() public override {
    super.setUp();
    _initLocking();
  }

  function test_getLock_shouldReturnCorrectValues() public {
    amount = 60000;
    slopePeriod = 30;
    cliff = 30;
    (uint96 lockAmount, uint96 lockSlope) = _subject();
    assertEq(lockAmount, 32903);
    assertEq(lockSlope, 1097);

    amount = 96000;
    slopePeriod = 48;
    cliff = 48;
    (lockAmount, lockSlope) = _subject();
    assertEq(lockAmount, 72713);
    assertEq(lockSlope, 1515);

    amount = 104000;
    slopePeriod = 104;
    cliff = 0;
    (lockAmount, lockSlope) = _subject();
    assertEq(lockAmount, 62400);
    assertEq(lockSlope, 600);

    amount = 104000;
    slopePeriod = 1;
    cliff = 103;
    (lockAmount, lockSlope) = _subject();
    assertEq(lockAmount, 104399);
    assertEq(lockSlope, 104399);
  }
}
