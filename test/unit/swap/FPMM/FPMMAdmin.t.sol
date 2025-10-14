// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";

contract FPMMAdminTest is FPMMBaseTest {
  event LPFeeUpdated(uint256 oldFee, uint256 newFee);
  event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
  event ProtocolFeeRecipientUpdated(address oldRecipient, address newRecipient);

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

  function test_setLPFee_whenOwner_shouldSetLPFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withProtocolFeeRecipient(feeRecipient)
  {
    vm.prank(owner);
    vm.expectEmit();
    emit LPFeeUpdated(30, 50);
    fpmm.setLPFee(50);

    assertEq(fpmm.lpFee(), 50);

    vm.startPrank(owner);
    fpmm.setProtocolFee(10);
    fpmm.setLPFee(90);
    vm.stopPrank();

    assertEq(fpmm.lpFee(), 90);
  }

  function test_setLPFee_whenFeeTooHigh_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withProtocolFeeRecipient(feeRecipient)
  {
    vm.prank(owner);
    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setLPFee(101);

    vm.startPrank(owner);
    fpmm.setProtocolFee(10);

    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setLPFee(91);
    vm.stopPrank();
  }

  function test_setProtocolFee_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setProtocolFee(10);
  }

  function test_setProtocolFee_whenOwner_shouldSetProtocolFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withProtocolFeeRecipient(feeRecipient)
  {
    vm.prank(owner);
    vm.expectEmit();
    emit ProtocolFeeUpdated(0, 50);
    fpmm.setProtocolFee(50);

    assertEq(fpmm.protocolFee(), 50);

    vm.startPrank(owner);
    fpmm.setLPFee(10);
    fpmm.setProtocolFee(90);
    vm.stopPrank();

    assertEq(fpmm.protocolFee(), 90);
  }

  function test_setProtocolFee_whenFeeIsZero_shouldNotRequireRecipient()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    vm.prank(owner);
    fpmm.setProtocolFee(0);

    assertEq(fpmm.protocolFee(), 0);
  }

  function test_setProtocolFee_whenFeeTooHigh_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    withProtocolFeeRecipient(feeRecipient)
  {
    vm.prank(owner);
    fpmm.setLPFee(0);

    vm.prank(owner);
    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setProtocolFee(101);

    vm.startPrank(owner);
    fpmm.setLPFee(10);

    vm.expectRevert("FPMM: FEE_TOO_HIGH");
    fpmm.setProtocolFee(91);
    vm.stopPrank();
  }

  function test_setProtocolFeeRecipient_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setProtocolFeeRecipient(address(0));
  }

  function test_setProtocolFeeRecipient_whenOwner_shouldSetProtocolFeeRecipient()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    vm.prank(owner);
    vm.expectEmit();
    emit ProtocolFeeRecipientUpdated(defaultFpmmConfig.protocolFeeRecipient, feeRecipient);
    fpmm.setProtocolFeeRecipient(feeRecipient);

    assertEq(fpmm.protocolFeeRecipient(), feeRecipient);
  }

  function test_setProtocolFeeRecipient_whenZeroAddress_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectRevert("FPMM: ZERO_ADDRESS");
    fpmm.setProtocolFeeRecipient(address(0));
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

  function test_setOracleAdapter_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setOracleAdapter(address(0));
  }

  function test_setReferenceRateFeedID_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setReferenceRateFeedID(address(0));
  }
}
