// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { ITradingLimitsV2 } from "contracts/interfaces/ITradingLimitsV2.sol";

contract FPMMAdminTest is FPMMBaseTest {
  event LPFeeUpdated(uint256 oldFee, uint256 newFee);
  event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
  event ProtocolFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
  event ReferenceRateFeedIDUpdated(address indexed oldRateFeedID, address indexed newRateFeedID);
  event OracleAdapterUpdated(address indexed oldOracleAdapter, address indexed newOracleAdapter);
  event LiquidityStrategyUpdated(address indexed strategy, bool status);
  event InvertRateFeedUpdated(bool oldInvertRateFeed, bool newInvertRateFeed);
  event TradingLimitConfigured(address indexed token, ITradingLimitsV2.Config config);

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
    vm.expectRevert(IFPMM.FeeTooHigh.selector);
    fpmm.setLPFee(101);

    vm.startPrank(owner);
    fpmm.setProtocolFee(10);

    vm.expectRevert(IFPMM.FeeTooHigh.selector);
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
    vm.expectRevert(IFPMM.FeeTooHigh.selector);
    fpmm.setProtocolFee(101);

    vm.startPrank(owner);
    fpmm.setLPFee(10);

    vm.expectRevert(IFPMM.FeeTooHigh.selector);
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
    emit ProtocolFeeRecipientUpdated(defaultFpmmParams.protocolFeeRecipient, feeRecipient);
    fpmm.setProtocolFeeRecipient(feeRecipient);

    assertEq(fpmm.protocolFeeRecipient(), feeRecipient);
  }

  function test_setProtocolFeeRecipient_whenZeroAddress_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectRevert(IFPMM.ZeroAddress.selector);
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

  function test_setLiquidityStrategy_whenZeroAddress_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectRevert(IFPMM.ZeroAddress.selector);
    fpmm.setLiquidityStrategy(address(0), true);
  }

  function test_setLiquidityStrategy_whenOwner_shouldSetLiquidityStrategy()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    address newLiquidityStrategy = makeAddr("newLiquidityStrategy");

    vm.prank(owner);
    vm.expectEmit();
    emit LiquidityStrategyUpdated(newLiquidityStrategy, true);
    fpmm.setLiquidityStrategy(newLiquidityStrategy, true);

    assertEq(fpmm.liquidityStrategy(newLiquidityStrategy), true);
  }

  function test_setOracleAdapter_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setOracleAdapter(address(0));
  }

  function test_setOracleAdapter_whenZeroAddress_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectRevert(IFPMM.ZeroAddress.selector);
    fpmm.setOracleAdapter(address(0));
  }

  function test_setOracleAdapter_whenOwner_shouldSetOracleAdapter() public initializeFPMM_withDecimalTokens(18, 18) {
    address newOracleAdapter = makeAddr("newOracleAdapter");

    vm.prank(owner);
    vm.expectEmit();
    emit OracleAdapterUpdated(address(oracleAdapter), newOracleAdapter);
    fpmm.setOracleAdapter(newOracleAdapter);
  }

  function test_setReferenceRateFeedID_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setReferenceRateFeedID(address(0));
  }

  function test_setReferenceRateFeedID_whenZeroAddress_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectRevert(IFPMM.ZeroAddress.selector);
    fpmm.setReferenceRateFeedID(address(0));
  }

  function test_setReferenceRateFeedID_whenOwner_shouldSetReferenceRateFeedID()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    address newReferenceRateFeedID = makeAddr("newReferenceRateFeedID");

    vm.prank(owner);
    vm.expectEmit();
    emit ReferenceRateFeedIDUpdated(referenceRateFeedID, newReferenceRateFeedID);
    fpmm.setReferenceRateFeedID(newReferenceRateFeedID);

    assertEq(fpmm.referenceRateFeedID(), newReferenceRateFeedID);
  }

  function test_setInvertRateFeed_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.setInvertRateFeed(true);
  }

  function test_setInvertRateFeed_whenOwner_shouldSetInvertRateFeed() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.startPrank(owner);
    vm.expectEmit();
    emit InvertRateFeedUpdated(false, true);
    fpmm.setInvertRateFeed(true);
    assertEq(fpmm.invertRateFeed(), true);

    vm.expectEmit();
    emit InvertRateFeedUpdated(true, false);
    fpmm.setInvertRateFeed(false);
    assertEq(fpmm.invertRateFeed(), false);
    vm.stopPrank();
  }

  function test_configureTradingLimit_whenNotOwner_shouldRevert() public {
    vm.prank(notOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    fpmm.configureTradingLimit(token0, 1000e18, 0);
  }

  function test_configureTradingLimit_whenInvalidToken_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    address invalidToken = makeAddr("INVALID_TOKEN");

    vm.prank(owner);
    vm.expectRevert(IFPMM.InvalidToken.selector);
    fpmm.configureTradingLimit(invalidToken, 1000e18, 0);
  }

  function test_configureTradingLimit_whenLimit1NotGreaterThanLimit0_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    vm.prank(owner);
    vm.expectRevert(ITradingLimitsV2.Limit1MustBeGreaterThanLimit0.selector);
    // Invalid: limit1 must be > limit0
    fpmm.configureTradingLimit(token0, 1000e18, 500e18);
  }

  function test_configureTradingLimit_whenOwner_shouldConfigureLimit() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    vm.expectEmit();
    emit TradingLimitConfigured(
      token0,
      ITradingLimitsV2.Config({ limit0: int120(1000e15), limit1: int120(10000e15), decimals: 18 })
    );
    fpmm.configureTradingLimit(token0, 1000e18, 10000e18);

    (ITradingLimitsV2.Config memory returnedConfig, ITradingLimitsV2.State memory returnedState) = fpmm
      .getTradingLimits(token0);

    assertEq(returnedConfig.limit0, 1000e15);
    assertEq(returnedConfig.limit1, 10000e15);
    assertEq(returnedState.netflow0, 0);
    assertEq(returnedState.netflow1, 0);
    assertEq(returnedState.lastUpdated0, 0);
    assertEq(returnedState.lastUpdated1, 0);
  }

  function test_configureTradingLimits_whenLimitExceedsInt120_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(15, 18) // 15 decimals for token0 so limit is not scaled down/up
  {
    // Limit0 exceeds int120
    vm.prank(owner);
    vm.expectRevert(IFPMM.LimitDoesNotFitInInt120.selector);
    fpmm.configureTradingLimit(token0, uint256(uint120(type(int120).max)) + 1, 0);

    // Limit1 exceeds int120
    vm.prank(owner);
    vm.expectRevert(IFPMM.LimitDoesNotFitInInt120.selector);
    fpmm.configureTradingLimit(token0, 0, uint256(uint120(type(int120).max)) + 1);
  }

  function test_getTradingLimits_whenInvalidToken_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    address invalidToken = makeAddr("INVALID_TOKEN");

    vm.expectRevert(IFPMM.InvalidToken.selector);
    fpmm.getTradingLimits(invalidToken);
  }

  function test_getTradingLimits_whenValidToken_shouldReturnLimits() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.prank(owner);
    fpmm.configureTradingLimit(token1, 5000e18, 50000e18);

    (ITradingLimitsV2.Config memory returnedConfig, ITradingLimitsV2.State memory returnedState) = fpmm
      .getTradingLimits(token1);

    assertEq(returnedConfig.limit0, 5000e15);
    assertEq(returnedConfig.limit1, 50000e15);
    assertEq(returnedState.netflow0, 0);
    assertEq(returnedState.netflow1, 0);
  }
}
