// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";

contract FPMMAdminTest is FPMMBaseTest {
  address public notOwner = makeAddr("NOT_OWNER");

  function setUp() public override {
    super.setUp();
    vm.stopPrank();
  }

  function test_setLPFee_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setLPFee(10);
  }

  function test_setRebalanceIncentive_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setRebalanceIncentive(10);
  }

  function test_setRebalanceThresholds_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setRebalanceThresholds(10, 10);
  }

  function test_setLiquidityStrategy_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setLiquidityStrategy(address(0), true);
  }

  function test_setSortedOracles_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setSortedOracles(address(0));
  }

  function test_setBreakerBox_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setBreakerBox(address(0));
  }

  function test_setReferenceRateFeedID_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setReferenceRateFeedID(address(0));
  }
}
