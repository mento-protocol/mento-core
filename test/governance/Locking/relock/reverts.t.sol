// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Relock_Locking_Test } from "./Base.t.sol";

contract Reverts_Relock_Locking_Test is Relock_Locking_Test {
  function setUp() public override {
    amount = 38;
    slopePeriod = 4;
    cliff = 3;

    super.setUp();
  }

  function test_relock_shouldRevert_whenAmountLessThanNow() public {
    _incrementBlock(4 * weekInBlocks);

    newAmount = 5;
    newSlopePeriod = 1;
    newCliff = 1;

    vm.expectRevert("Impossible to relock: less amount, then now is");
    vm.startPrank(alice);
    _subject();
  }

  function test_relock_shouldRevert_whenPeriodTooShort() public {
    newAmount = 5;
    newSlopePeriod = 1;
    newCliff = 1;

    vm.expectRevert("new line period lock too short");
    vm.startPrank(alice);
    _subject();
  }

  function test_relock_shouldRevert_whenAmountIsZero() public {
    newAmount = 0;
    newSlopePeriod = 5;
    newCliff = 1;

    vm.expectRevert("zero amount");
    vm.startPrank(alice);
    _subject();
  }

  function test_relock_shouldRevert_whenSlopeIsZero() public {
    newAmount = 60;
    newSlopePeriod = 0;
    newCliff = 2;

    vm.expectRevert("slope period equal 0");
    vm.startPrank(alice);
    _subject();
  }

  function test_relock_shouldRevert_whenCliffIsLong() public {
    newAmount = 60;
    newSlopePeriod = 12;
    newCliff = 105;

    vm.expectRevert("cliff too big");
    vm.startPrank(alice);
    _subject();
  }

  function test_relock_shouldRevert_whenSlopeIsLong() public {
    newAmount = 1050;
    newSlopePeriod = 210;
    newCliff = 10;

    vm.expectRevert("slope period too big");
    vm.startPrank(alice);
    _subject();
  }
}
