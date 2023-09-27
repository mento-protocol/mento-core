// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract Init_Locking_Test is Locking_Test {
  function _subject() internal {
    _initLocking();
  }

  function test_init_shouldSetState() public {
    _subject();

    assertEq(address(lockingContract.token()), address(mentoToken));

    assertEq(lockingContract.startingPointWeek(), 0);
    assertEq(lockingContract.minCliffPeriod(), 0);
    assertEq(lockingContract.minSlopePeriod(), 0);
    assertEq(lockingContract.owner(), owner);
  }
}
