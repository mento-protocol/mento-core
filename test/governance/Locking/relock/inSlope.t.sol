// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Relock_Locking_Test } from "./Base.t.sol";

contract InSlope_Relock_Locking_Test is Relock_Locking_Test {
  function setUp() public override {
    amount = 30;
    slopePeriod = 3;
    cliff = 0;

    super.setUp();
  }

  function test_relock_shouldChangeAllParams_AndContinueReleasingByNewSchedule() public {
    newAmount = 80;
    newSlopePeriod = 16;
    newCliff = 6;

    vm.startPrank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(6 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(16 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }

  function test_relock_shouldReleaseBySameSchedule_whenWithdrawBeforeRelock() public {
    newAmount = 80;
    newSlopePeriod = 16;
    newCliff = 6;

    vm.startPrank(alice);

    lockingContract.withdraw();
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(6 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 80);
    assertEq(mentoToken.balanceOf(alice), 20);

    _incrementBlock(16 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }
}
