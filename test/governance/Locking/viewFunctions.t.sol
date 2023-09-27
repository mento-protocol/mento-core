// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Locking_Test } from "./Base.t.sol";

contract ViewFunctions_Locking_Test is Locking_Test {
  uint256 public aliceBalance = 1000000;

  uint256 public lockId;
  uint256 public lockBlock;
  uint256 public voteBlock;
  uint256 public delegateBlock;
  uint256 public relockBlock;

  function setUp() public override {
    super.setUp();
    _initLocking();
    weekInBlocks = uint32(lockingContract.WEEK());

    _incrementBlock(weekInBlocks + 1);

    mentoToken.mint(alice, aliceBalance);

    vm.prank(alice);
    mentoToken.approve(address(lockingContract), type(uint256).max);

    _incrementBlock(weekInBlocks / 2);

    lockBlock = lockingContract.blockNumberMocked();

    vm.prank(alice);
    lockId = lockingContract.lock(alice, alice, 3000, 3, 0);
  }

  function test_viewFuctions_shouldReturnCorrectValues_whenAfterALockCreated() public {
    // WEEK 1
    assertEq(mentoToken.balanceOf(address(lockingContract)), 3000);
    assertEq(lockingContract.balanceOf(alice), 634);
    assertEq(lockingContract.getVotes(alice), 634);

    // WEEK 2
    _incrementBlock(weekInBlocks / 2 + weekInBlocks / 4);

    delegateBlock = lockingContract.blockNumberMocked();
    voteBlock = delegateBlock + weekInBlocks / 4;

    assertEq(lockingContract.balanceOf(alice), 422);
    assertEq(lockingContract.getVotes(alice), 422);

    vm.prank(alice);
    lockingContract.delegateTo(lockId, bob);

    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 422);
    assertEq(lockingContract.getVotes(bob), 422);

    assertEq(lockingContract.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(lockingContract.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(lockingContract.getPastTotalSupply(delegateBlock - 1), 422);

    _incrementBlock(weekInBlocks / 2);

    relockBlock = lockingContract.blockNumberMocked();

    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 422);
    assertEq(lockingContract.getVotes(bob), 422);

    assertEq(lockingContract.getPastVotes(alice, voteBlock), 0);
    assertEq(lockingContract.getPastVotes(bob, voteBlock), 422);
    assertEq(lockingContract.getPastTotalSupply(voteBlock), 422);

    assertEq(lockingContract.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(lockingContract.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(lockingContract.getPastTotalSupply(delegateBlock - 1), 422);

    vm.prank(alice);
    lockingContract.relock(lockId, charlie, 4000, 4, 0);

    assertEq(mentoToken.balanceOf(address(lockingContract)), 4000);
    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.getVotes(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 861);
    assertEq(lockingContract.getVotes(charlie), 861);

    assertEq(lockingContract.getPastVotes(alice, voteBlock), 0);
    assertEq(lockingContract.getPastVotes(bob, voteBlock), 422);
    assertEq(lockingContract.getPastTotalSupply(voteBlock), 422);

    assertEq(lockingContract.getPastVotes(alice, delegateBlock - 1), 422);
    assertEq(lockingContract.getPastVotes(bob, delegateBlock - 1), 0);
    assertEq(lockingContract.getPastTotalSupply(delegateBlock - 1), 422);

    assertEq(lockingContract.getPastVotes(alice, relockBlock - 1), 0);
    assertEq(lockingContract.getPastVotes(bob, relockBlock - 1), 422);
    assertEq(lockingContract.getPastTotalSupply(relockBlock - 1), 422);

    // WEEK 3

    _incrementBlock(weekInBlocks / 4);
    assertEq(lockingContract.balanceOf(alice), 0);
    assertEq(lockingContract.getVotes(alice), 0);
    assertEq(lockingContract.balanceOf(bob), 0);
    assertEq(lockingContract.getVotes(bob), 0);
    assertEq(lockingContract.balanceOf(charlie), 645);
    assertEq(lockingContract.getVotes(charlie), 645);

    uint256 currentBlock = lockingContract.blockNumberMocked();

    vm.expectRevert("block not yet mined");
    lockingContract.getPastVotes(alice, currentBlock);

    vm.expectRevert("block not yet mined");
    lockingContract.getPastTotalSupply(currentBlock);
  }
}
