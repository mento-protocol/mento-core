// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "../../Base.t.sol";

contract MultipleLines_Relock_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 100;
  uint256 public weekInBlocks;

  address public account1 = alice;
  address public delegate1 = alice;
  uint96 public amount1;
  uint32 public slopePeriod1;
  uint32 public cliff1;

  address public account2 = alice;
  address public delegate2 = alice;
  uint96 public amount2;
  uint32 public slopePeriod2;
  uint32 public cliff2;

  uint256 public lockId1;
  uint256 public lockId2;

  uint256 public lockId;
  address public newDelegate = alice;
  uint96 public newAmount;
  uint32 public newSlopePeriod;
  uint32 public newCliff;

  function _subject() internal returns (uint256) {
    return lockingContract.relock(lockId, newDelegate, newAmount, newSlopePeriod, newCliff);
  }

  function setUp() public virtual override {
    super.setUp();
    _initLocking();

    weekInBlocks = lockingContract.WEEK();

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    vm.roll(2 * weekInBlocks + 1);

    vm.prank(alice);
    lockId1 = lockingContract.lock(account1, delegate1, amount1, slopePeriod1, cliff1);

    vm.prank(alice);
    lockId2 = lockingContract.lock(account2, delegate2, amount2, slopePeriod2, cliff2);

    vm.roll(block.number + 2 * weekInBlocks);
  }
}
