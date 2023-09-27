// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "../Base.t.sol";

contract Relock_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 100;

  address public account = alice;
  address public delegate = alice;
  uint96 public amount;
  uint32 public slopePeriod;
  uint32 public cliff;

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

    weekInBlocks = uint32(lockingContract.WEEK());

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    _incrementBlock(2 * weekInBlocks + 1);

    vm.prank(alice);
    lockId = lockingContract.lock(account, delegate, amount, slopePeriod, cliff);

    _incrementBlock(2 * weekInBlocks);
  }
}
