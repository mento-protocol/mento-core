// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract GetAvailableForWithdraw_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 100;
  uint256 public weekInBlocks;

  address public account = alice;
  address public delegate = alice;
  uint96 public amount = 30;
  uint32 public slopePeriod = 3;
  uint32 public cliff = 0;

  function _lock() internal returns (uint256) {
    return lockingContract.lock(account, delegate, amount, slopePeriod, cliff);
  }

  function _subject() internal returns (uint256) {
    return lockingContract.getAvailableForWithdraw(account);
  }

  function setUp() public override {
    super.setUp();
    _initLocking();

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);
    weekInBlocks = lockingContract.WEEK();

    vm.roll(2 * weekInBlocks + 1);
  }

  function test_getAvailableForWithdraw_shouldReturnCorrectAmount() public {
    vm.prank(alice);
    _lock();

    vm.roll(block.number + 2 * weekInBlocks);

    vm.prank(alice);
    uint256 availableForWithdraw = _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 30);
    assertEq(mentoToken.balanceOf(alice), 70);
    assertEq(availableForWithdraw, 20);
  }
}
