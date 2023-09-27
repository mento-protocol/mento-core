// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract Lock_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 1500;

  address public account;
  address public delegate;
  uint96 public amount;
  uint32 public slopePeriod;
  uint32 public cliff;

  function _subject() internal returns (uint256) {
    return lockingContract.lock(account, delegate, amount, slopePeriod, cliff);
  }

  function setUp() public override {
    super.setUp();
    _initLocking();

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    weekInBlocks = uint32(lockingContract.WEEK());

    _incrementBlock(2 * weekInBlocks + 1);
  }

  function test_lock_shouldRevert_whenSlopeIsLarge() public {
    account = alice;
    delegate = alice;
    amount = 1000;
    slopePeriod = 105;
    cliff = 0;

    vm.expectRevert("period too big");
    vm.prank(alice);
    _subject();
  }

  function test_lock_shouldRevert_whenCliffeIsLarge() public {
    account = alice;
    delegate = alice;
    amount = 1000;
    slopePeriod = 11;
    cliff = 105;

    vm.expectRevert("cliff too big");
    vm.prank(alice);
    _subject();
  }

  function test_lock_shouldRevert_whenAmountIsZero() public {
    account = alice;
    delegate = alice;
    amount = 0;
    slopePeriod = 10;
    cliff = 10;

    vm.expectRevert("zero amount");
    vm.prank(alice);
    _subject();
  }

  function test_lock_shouldRevert_whenSlopeIsZero() public {
    account = alice;
    delegate = alice;
    amount = 1000;
    slopePeriod = 0;
    cliff = 10;

    vm.expectRevert();
    vm.prank(alice);
    _subject();
  }

  function test_lock_shouldRevert_whenSlopeBiggerThanAmount() public {
    account = alice;
    delegate = alice;
    amount = 20;
    slopePeriod = 40;
    cliff = 0;

    vm.expectRevert("Wrong value slopePeriod");
    vm.prank(alice);
    _subject();
  }

  function test_lock_shouldMintVotesCorrectly_whenMaxCliff() public {
    account = alice;
    delegate = alice;
    amount = 1000;
    slopePeriod = 1;
    cliff = 103;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 1000);
    assertEq(mentoToken.balanceOf(alice), 500);
    assertEq(lockingContract.balanceOf(alice), 1003);
    assertEq(lockingContract.getVotes(alice), 1003);
    assertEq(lockingContract.totalSupply(), 1003);
    assertEq(lockingContract.locked(alice), 1000);
  }

  function test_lock_shouldMintVotesCorrectly_whenOnlySlope() public {
    account = alice;
    delegate = alice;
    amount = 1000;
    slopePeriod = 10;
    cliff = 0;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(address(lockingContract)), 1000);
    assertEq(mentoToken.balanceOf(alice), 500);
    assertEq(lockingContract.balanceOf(alice), 238);
    assertEq(lockingContract.getVotes(alice), 238);
    assertEq(lockingContract.totalSupply(), 238);
    assertEq(lockingContract.locked(alice), 1000);
  }

  function test_lock_shouldSetDelegate() public {
    account = alice;
    delegate = bob;
    amount = 1000;
    slopePeriod = 10;
    cliff = 0;

    vm.prank(alice);
    uint256 lockId = _subject();

    (address account_, address delegate_) = lockingContract.getAccountAndDelegate(lockId);
    assertEq(account_, alice);
    assertEq(delegate_, bob);
  }
}
