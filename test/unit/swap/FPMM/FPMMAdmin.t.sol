// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";

import { IFPMM } from "contracts/interfaces/IFPMM.sol";

contract FPMMAdminTest is FPMMBaseTest {
  address public notOwner = makeAddr("NOT_OWNER");
  address public feeRecipient = makeAddr("FEE_RECIPIENT");

  function setUp() public override {
    super.setUp();
    vm.stopPrank();
  }

  function test_setLPFee_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setLPFee(10);
  }

  function test_setLPFee_whenOwner_shouldSetLPFee() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectEmit();
    emit IFPMM.LPFeeUpdated(30, 50);
    fpmm.setLPFee(50);

    assertEq(fpmm.lpFee(), 50);

    vm.startPrank(owner);
    fpmm.setProtocolFee(10, feeRecipient);
    fpmm.setLPFee(90);
    vm.stopPrank();

    assertEq(fpmm.lpFee(), 90);
  }

  function test_setLPFee_whenFeeTooHigh_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setLPFee(101);

    vm.startPrank(owner);
    fpmm.setProtocolFee(10, feeRecipient);

    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setLPFee(91);
    vm.stopPrank();
  }

  function test_setProtocolFee_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setProtocolFee(10, feeRecipient);
  }

  function test_setProtocolFee_whenOwner_shouldSetProtocolFee() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectEmit();
    emit IFPMM.ProtocolFeeUpdated(0, 50, address(0), feeRecipient);
    fpmm.setProtocolFee(50, feeRecipient);

    assertEq(fpmm.protocolFee(), 50);
    assertEq(fpmm.protocolFeeRecipient(), feeRecipient);

    vm.startPrank(owner);
    fpmm.setLPFee(10);
    fpmm.setProtocolFee(90, feeRecipient);
    vm.stopPrank();

    assertEq(fpmm.protocolFee(), 90);
  }

  function test_setProtocolFee_whenFeeIsZero_shouldNotRequireRecipient()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    vm.prank(owner);
    fpmm.setProtocolFee(0, address(0));

    assertEq(fpmm.protocolFee(), 0);
    assertEq(fpmm.protocolFeeRecipient(), address(0));
  }

  function test_setProtocolFee_whenFeeIsNotZero_shouldRequireRecipient()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    vm.prank(owner);
    vm.expectRevert("FPMM: PROTOCOL_FEE_RECIPIENT_REQUIRED");
    fpmm.setProtocolFee(10, address(0));
  }

  function test_setProtocolFee_whenFeeTooHigh_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    fpmm.setLPFee(0);

    vm.prank(owner);
    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setProtocolFee(101, feeRecipient);

    vm.startPrank(owner);
    fpmm.setLPFee(10);

    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setProtocolFee(91, feeRecipient);
    vm.stopPrank();
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
