// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Relock_Locking_Test } from "./Base.t.sol";

contract InTail_Relock_Locking_Test is Relock_Locking_Test {
  function setUp() public override {
    amount = 37;
    slopePeriod = 4;
    cliff = 3;

    super.setUp();

    vm.roll(block.number + 4 * weekInBlocks);
  }

  function test_relock_shouldChangeAllParams_AndContinueReleasingByNewSchedule() public {
    newAmount = 10;
    newSlopePeriod = 2;
    newCliff = 2;

    vm.startPrank(alice);
    _subject();

    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    vm.roll(block.number + 2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    vm.roll(block.number + 2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }

  function test_relock_shouldChangeAllParams_AndTransferMoreTokensToRelock() public {
    lockingContract.withdraw();

    newAmount = 10;
    newSlopePeriod = 2;
    newCliff = 2;

    vm.startPrank(alice);
    _subject();

    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    vm.roll(block.number + 2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 10);
    assertEq(mentoToken.balanceOf(alice), 90);

    vm.roll(block.number + 2 * weekInBlocks);
    lockingContract.withdraw();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 0);
    assertEq(mentoToken.balanceOf(alice), 100);

    vm.stopPrank();
  }
}
