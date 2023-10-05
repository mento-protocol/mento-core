// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;
// solhint-disable state-visibility

import { TestERC20 } from "../../utils/TestERC20.sol";
import { TestLocking } from "../../utils/TestLocking.sol";
import { Vm } from "forge-std/Vm.sol";
import { DSTest } from "ds-test/test.sol";

/**
 * @notice https://github.com/rarible/locking-contracts/tree/4f189a96b3e85602dedfbaf69d9a1f5056d835eb
 */
contract FuzzTestLocking is TestLocking, DSTest {
  Vm internal immutable vm = Vm(HEVM_ADDRESS);

  TestERC20 public testERC20;

  address user0;
  address user1;

  function setUp() public {
    user0 = address(100);
    vm.deal(user0, 100 ether);
    user1 = address(200);
    vm.deal(user1, 100 ether);
    testERC20 = new TestERC20();
    this.__Locking_init(testERC20, 0, 1, 3);

    this.incrementBlock(this.WEEK() + 1);
  }

  function testLockAmount(uint96 amount) public {
    vm.assume(amount < 2**95);
    vm.assume(amount > 1000);
    prepareTokens(user0, amount);
    lockTokens(user0, user0, uint96(amount), 100, 100);
  }

  function testLockSlope(uint32 slope) public {
    vm.assume(slope >= minSlopePeriod);
    vm.assume(slope <= MAX_SLOPE_PERIOD);

    uint96 amount = 100 * (10**18);

    prepareTokens(user0, amount);
    lockTokens(user0, user0, uint96(amount), slope, 100);
  }

  function testLockCliff(uint32 cliff) public {
    vm.assume(cliff >= minCliffPeriod);
    vm.assume(cliff <= MAX_CLIFF_PERIOD);

    uint96 amount = 100 * (10**18);

    prepareTokens(user0, amount);
    lockTokens(user0, user0, uint96(amount), 100, cliff);
  }

  function prepareTokens(address user, uint256 amount) public {
    testERC20.mint(user, amount);
    vm.prank(user);
    testERC20.approve(address(this), amount);
    assertEq(testERC20.balanceOf(user), amount);
    assertEq(testERC20.allowance(user, address(this)), amount);
  }

  function lockTokens(
    address user,
    address delegate,
    uint96 amount,
    uint32 slopePeriod,
    uint32 cliff
  ) public {
    vm.prank(user);
    this.lock(user, delegate, amount, slopePeriod, cliff);

    assertEq(this.locked(user), amount);
  }
}
