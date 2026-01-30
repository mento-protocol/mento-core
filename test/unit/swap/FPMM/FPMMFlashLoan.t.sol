// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { FlashLoanReceiver } from "./helpers/FlashLoanReceiver.sol";
import { ReentrancyExploiter } from "./helpers/ReentrancyExploiter.sol";
import { MockExchange } from "./helpers/MockExchange.sol";
import { ArbitrageFlashLoanReceiver } from "./helpers/ArbitrageFlashLoanReceiver.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

contract FPMMFlashLoanTest is FPMMBaseTest {
  address public flashLoanReceiver;
  MockExchange public exchange;

  enum ReceiverType {
    FlashLoanReceiver,
    ArbitrageFlashLoanReceiver,
    ReentrancyExploiter
  }

  function setUp() public override {
    super.setUp();
  }

  modifier setupFlashLoanReceiver(uint8 decimals0, uint8 decimals1, ReceiverType receiverType) {
    if (receiverType == ReceiverType.FlashLoanReceiver) {
      flashLoanReceiver = address(new FlashLoanReceiver(address(fpmm), token0, token1));
    } else if (receiverType == ReceiverType.ArbitrageFlashLoanReceiver) {
      flashLoanReceiver = address(new ArbitrageFlashLoanReceiver(address(fpmm), address(exchange), token0, token1));
    } else if (receiverType == ReceiverType.ReentrancyExploiter) {
      flashLoanReceiver = address(new ReentrancyExploiter(address(fpmm), token0, token1));
    }
    deal(token0, address(flashLoanReceiver), 1000 * 10 ** decimals0);
    deal(token1, address(flashLoanReceiver), 1000 * 10 ** decimals1);
    _;
  }

  modifier setupMockExchange(uint256 exchangeRate) {
    exchange = new MockExchange(token0, token1, exchangeRate);
    deal(token0, address(exchange), 1000e18);
    deal(token1, address(exchange), 1000e18);
    _;
  }

  function test_swap_whenBorrowingToken0_shouldTransferAndRepayWithFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount = 50e18;
    bytes memory customData = abi.encode("Custom flash loan data");

    uint256 swapFee0 = (flashLoanAmount * 10_000) / (10_000 - 30) - flashLoanAmount;

    // Set to repay with extra fee
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, swapFee0, 0);

    fpmm.swap(flashLoanAmount, 0, address(flashLoanReceiver), customData);

    assertEq(FlashLoanReceiver(flashLoanReceiver).sender(), address(this));
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), flashLoanAmount);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), 0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).receivedData(), customData);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100_000e18 + swapFee0); // Initial 100e18 + fee
    assertEq(fpmm.reserve1(), 200_000e18); // Unchanged
  }

  function test_swap_whenBorrowingToken0WithProtocolFee_shouldCorrectlyHandleFees()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withProtocolFee(20, protocolFeeRecipient)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 loan = 50e18;
    uint256 fee = (loan * 10_000) / (10_000 - 50) - loan; // 50bps fee (30bps LP fee + 20bps protocol fee)
    uint256 lpFeeCut = (fee * (30)) / 50;
    uint256 protocolFeeCut = fee - lpFeeCut;

    uint256 beforeReserve0 = fpmm.reserve0();
    uint256 beforeReserve1 = fpmm.reserve1();

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);

    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, fee, 0);
    fpmm.swap(loan, 0, address(flashLoanReceiver), bytes("flash loan data"));

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), protocolFeeCut);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);
    assertEq(fpmm.reserve0(), beforeReserve0 + lpFeeCut);
    assertEq(fpmm.reserve1(), beforeReserve1);
  }

  function test_swap_whenLoanRepaidOnTokenWithDifferentExchangeRate_shouldCorrectlyHandleFees()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(5e23, 1e24)
    withProtocolFee(20, protocolFeeRecipient)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 loan = 50e18;
    uint256 fee = (loan * 10_000) / (10_000 - 50) - loan;
    uint256 feeInToken1 = fee / 2; // Repay in token1 which has a 2:1 exchange rate

    uint256 expectedLpFeeT0 = (fee * (30)) / 50;
    uint256 expectedProtocolFeeT0 = fee - expectedLpFeeT0;

    uint256 beforeReserve0 = fpmm.reserve0();
    uint256 beforeReserve1 = fpmm.reserve1();

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);

    // try to pay back slightly less than expected at the 2:1 rate
    FlashLoanReceiver(flashLoanReceiver).enableRepayExactAmounts(loan, feeInToken1 - 1);
    vm.expectRevert(IFPMM.ReserveValueDecreased.selector);
    fpmm.swap(loan, 0, address(flashLoanReceiver), bytes("flash loan data"));

    FlashLoanReceiver(flashLoanReceiver).enableRepayExactAmounts(loan, feeInToken1);
    fpmm.swap(loan, 0, address(flashLoanReceiver), bytes("flash loan data"));

    uint256 takenProtocolFeeT0 = (loan * 20) / 10_000;
    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), takenProtocolFeeT0);
    assertEq(fpmm.reserve0(), beforeReserve0 - takenProtocolFeeT0);

    uint256 expectedProtocolFeeT1 = (expectedProtocolFeeT0 - takenProtocolFeeT0) / 2;
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), expectedProtocolFeeT1);

    uint256 expectedLpFeeT1 = feeInToken1 - expectedProtocolFeeT1;
    assertEq(fpmm.reserve1(), beforeReserve1 + expectedLpFeeT1);
  }

  function test_swap_whenBorrowingToken0WithProtocolFee_shouldAllowFeeToBeRepaidInBothTokens()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withProtocolFee(20, protocolFeeRecipient)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 loan = 50e18;
    uint256 fee = (loan * 10_000) / (10_000 - 50) - loan;
    uint256 lpFeeCut = (fee * (30)) / 50;
    uint256 protocolFeeCut = fee - lpFeeCut;

    uint256 beforeReserve0 = fpmm.reserve0();
    uint256 beforeReserve1 = fpmm.reserve1();

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);

    uint256 halfFee = fee / 2;
    uint256 remainingFee = fee - halfFee;

    // Repay the loan and fees in both tokens:
    uint256 token0Payback = loan + halfFee;
    uint256 token1Payback = remainingFee;
    FlashLoanReceiver(flashLoanReceiver).enableRepayExactAmounts(token0Payback, token1Payback);
    fpmm.swap(loan, 0, address(flashLoanReceiver), bytes("flash loan data"));

    uint256 protocolFeeCutInToken0 = ((token0Payback) * (20)) / 10_000;
    uint256 protocolFeeCutInToken1 = protocolFeeCut - protocolFeeCutInToken0;

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), protocolFeeCutInToken0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), protocolFeeCutInToken1);
    assertEq(fpmm.reserve0() + fpmm.reserve1(), beforeReserve0 + beforeReserve1 + lpFeeCut);
  }

  function test_swap_whenBorrowingToken1_shouldTransferAndRepayWithFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount = 50e18;
    bytes memory customData = abi.encode("Custom flash loan data");

    uint256 swapFee1 = (flashLoanAmount * 10_000) / (10_000 - 30) - flashLoanAmount;

    // Set to repay with extra fee
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, 0, swapFee1);

    fpmm.swap(0, flashLoanAmount, flashLoanReceiver, customData);

    assertEq(FlashLoanReceiver(flashLoanReceiver).sender(), address(this));
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), 0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), flashLoanAmount);
    assertEq(FlashLoanReceiver(flashLoanReceiver).receivedData(), customData);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100_000e18); // Unchanged
    assertEq(fpmm.reserve1(), 200_000e18 + swapFee1); // Initial 200e18 + fee
  }

  function test_swap_whenBorrowingToken1WithProtocolFee_shouldCorrectlyHandleFees()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withProtocolFee(70, protocolFeeRecipient)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 loan = 74e17;
    uint256 fee = (loan * 10_000) / (10_000 - 100) - loan; // 100bps fee (30bps LP fee + 70bps protocol fee)
    uint256 lpFeeCut = (fee * (30)) / 100;
    uint256 protocolFeeCut = fee - lpFeeCut;

    uint256 beforeReserve0 = fpmm.reserve0();
    uint256 beforeReserve1 = fpmm.reserve1();

    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);

    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, 0, fee);
    fpmm.swap(0, loan, address(flashLoanReceiver), bytes("flash loan data"));

    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), protocolFeeCut);
    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(fpmm.reserve0(), beforeReserve0);
    assertEq(fpmm.reserve1(), beforeReserve1 + lpFeeCut);
  }

  function test_swap_whenBorrowingBothTokens_shouldTransferAndRepayWithFee()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount0 = 30e18;
    uint256 flashLoanAmount1 = 40e18;
    bytes memory customData = abi.encode("Custom flash loan data");

    uint256 swapFee0 = (flashLoanAmount0 * 10_000) / (10_000 - 30) - flashLoanAmount0;
    uint256 swapFee1 = (flashLoanAmount1 * 10_000) / (10_000 - 30) - flashLoanAmount1;

    // Set to repay with extra fee
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, swapFee0, swapFee1);

    fpmm.swap(flashLoanAmount0, flashLoanAmount1, address(flashLoanReceiver), customData);

    assertEq(FlashLoanReceiver(flashLoanReceiver).sender(), address(this));
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), flashLoanAmount0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), flashLoanAmount1);
    assertEq(FlashLoanReceiver(flashLoanReceiver).receivedData(), customData);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100_000e18 + swapFee0); // Initial 100e18 + fee
    assertEq(fpmm.reserve1(), 200_000e18 + swapFee1); // Initial 200e18 + fee
  }

  function test_swap_whenBorrowingBothTokensWithProtocolFee_shouldCorrectlyHandleFees()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withProtocolFee(20, protocolFeeRecipient)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 loan0 = 30e18;
    uint256 loan1 = 40e18;
    uint256 fee0 = (loan0 * 10_000) / (10_000 - 50) - loan0;
    uint256 fee1 = (loan1 * 10_000) / (10_000 - 50) - loan1;
    uint256 lpFeeCut0 = (fee0 * (30)) / 50;
    uint256 lpFeeCut1 = (fee1 * (30)) / 50;
    uint256 protocolFeeCut0 = fee0 - lpFeeCut0;
    uint256 protocolFeeCut1 = fee1 - lpFeeCut1;

    uint256 beforeReserve0 = fpmm.reserve0();
    uint256 beforeReserve1 = fpmm.reserve1();

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);

    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, fee0, fee1);
    fpmm.swap(loan0, loan1, address(flashLoanReceiver), bytes("flash loan data"));

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), protocolFeeCut0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), protocolFeeCut1);
    assertEq(fpmm.reserve0(), beforeReserve0 + lpFeeCut0);
    assertEq(fpmm.reserve1(), beforeReserve1 + lpFeeCut1);
  }

  function test_swap_whenLoanNotRepaid_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount = 50e18;

    // Set NOT to repay
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(false, 0, 0);

    // Flash loan should fail because it's not repaid
    vm.expectRevert(IFPMM.InsufficientInputAmount.selector);
    fpmm.swap(flashLoanAmount, 0, address(flashLoanReceiver), "data");
  }

  function test_swap_whenPaidLessThanRequired_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount = 50e18;
    uint256 lessThanRequiredFee0 = (flashLoanAmount * 10_000) / (10_000 - 30) - flashLoanAmount;
    lessThanRequiredFee0 = lessThanRequiredFee0 - 1;

    // Pay back less than required
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, lessThanRequiredFee0, 0);

    // Flash loan should fail because it's not repaid correctly
    vm.expectRevert(IFPMM.ReserveValueDecreased.selector);
    fpmm.swap(flashLoanAmount, 0, address(flashLoanReceiver), "data");
  }

  function test_swap_whenNotEnoughCombinedFeeRepaid_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withProtocolFee(20, protocolFeeRecipient)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount = 50e18;
    uint256 combinedFeeBps = 50;
    uint256 fee = (flashLoanAmount * 10_000) / (10_000 - combinedFeeBps) - flashLoanAmount;
    uint256 almostFullFee = fee - 1;

    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, almostFullFee, 0);

    vm.expectRevert(IFPMM.ReserveValueDecreased.selector);
    fpmm.swap(flashLoanAmount, 0, address(flashLoanReceiver), "data");
  }

  function test_swap_whenReceiverReverts_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount = 50e18;

    // Make the receiver revert in the hook
    FlashLoanReceiver(flashLoanReceiver).setRevertInHook(true);

    // Flash loan should fail because the receiver reverts
    vm.expectRevert("FlashLoanReceiver: Reverting as requested");
    fpmm.swap(flashLoanAmount, 0, flashLoanReceiver, "data");
  }

  function test_swap_whenUsingMaxAmounts_shouldSucceed()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // Try to flash loan the maximum amount
    uint256 maxToken0Amount = fpmm.reserve0() - 1;
    uint256 maxToken1Amount = fpmm.reserve1() - 1;

    uint256 swapFee0 = (maxToken0Amount * 10_000) / (10_000 - 30) - maxToken0Amount;
    uint256 swapFee1 = (maxToken1Amount * 10_000) / (10_000 - 30) - maxToken1Amount;

    // Ensure the flash loan receiver has enough tokens to repay
    deal(token0, flashLoanReceiver, swapFee0);
    deal(token1, flashLoanReceiver, swapFee1);

    // Set to repay with extra fee (simplified to 1e18 for test)
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, swapFee0, swapFee1);

    fpmm.swap(maxToken0Amount, maxToken1Amount, flashLoanReceiver, "Max flash loan test");

    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), maxToken0Amount);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), maxToken1Amount);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100_000e18 + swapFee0); // Initial + fee
    assertEq(fpmm.reserve1(), 200_000e18 + swapFee1); // Initial + fee
  }

  function test_swap_whenTokensHaveDifferentDecimals_shouldHandleCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    setupFlashLoanReceiver(18, 6, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 flashLoanAmount0 = 30e18; // 18 decimals
    uint256 flashLoanAmount1 = 40e6; // 6 decimals

    uint256 swapFee0 = (flashLoanAmount0 * 10_000) / (10_000 - 30) - flashLoanAmount0;
    uint256 swapFee1 = (flashLoanAmount1 * 10_000) / (10_000 - 30) - flashLoanAmount1;

    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, swapFee0, swapFee1);

    fpmm.swap(flashLoanAmount0, flashLoanAmount1, flashLoanReceiver, "Different decimals");

    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), flashLoanAmount0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), flashLoanAmount1);

    assertEq(fpmm.reserve0(), 100_000e18 + swapFee0); // Initial + fee
    assertEq(fpmm.reserve1(), 200_000e6 + swapFee1); // Initial + fee
  }

  function test_swap_whenLoanRepaidInTokenWithDifferentDecimals_shouldHandleCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    setupFlashLoanReceiver(18, 6, ReceiverType.FlashLoanReceiver)
    withOracleRate(1e24, 1e24)
    withProtocolFee(20, protocolFeeRecipient)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 loan = 30e18;
    uint256 scaledLoan = loan / 1e12;
    uint256 fee = (loan * 10_000) / (10_000 - 50) - loan;
    uint256 feeScaled = fee / 1e12;

    uint256 expectedProtocolFee = (feeScaled * 20) / 50;

    uint256 beforeReserve0 = fpmm.reserve0();
    uint256 beforeReserve1 = fpmm.reserve1();

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);

    uint256 expectedRepayInT1 = scaledLoan + feeScaled;

    FlashLoanReceiver(flashLoanReceiver).enableRepayExactAmounts(0, expectedRepayInT1 - 1);
    vm.expectRevert(IFPMM.ReserveValueDecreased.selector);
    fpmm.swap(loan, 0, address(flashLoanReceiver), "loan");

    FlashLoanReceiver(flashLoanReceiver).enableRepayExactAmounts(0, expectedRepayInT1);
    fpmm.swap(loan, 0, address(flashLoanReceiver), "loan");

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), expectedProtocolFee);
    assertEq(fpmm.reserve0(), beforeReserve0 - loan);
    assertEq(fpmm.reserve1(), beforeReserve1 + expectedRepayInT1 - expectedProtocolFee);
  }

  function test_swap_whenLoanRepaidInDifferentRateAndDecimals_shouldHandleCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    setupFlashLoanReceiver(18, 6, ReceiverType.FlashLoanReceiver)
    withOracleRate(4e23, 1e24)
    withProtocolFee(20, protocolFeeRecipient)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    uint256 loan = 50e18;
    uint256 scaledLoan = loan / 2.5e12;
    uint256 fee = (loan * 10_000) / (10_000 - 50) - loan;
    uint256 scaledFee = fee / 2.5e12;

    uint256 expectedRepaymentT1 = scaledLoan + scaledFee;
    uint256 expectedProtocolFeeT1 = (expectedRepaymentT1 * 20) / 10_000;
    uint256 expectedLpFeeT1 = scaledFee - expectedProtocolFeeT1;

    uint256 beforeReserve0 = fpmm.reserve0();
    uint256 beforeReserve1 = fpmm.reserve1();

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), 0);

    FlashLoanReceiver(flashLoanReceiver).enableRepayExactAmounts(0, expectedRepaymentT1 - 1);
    vm.expectRevert(IFPMM.ReserveValueDecreased.selector);
    fpmm.swap(loan, 0, address(flashLoanReceiver), "loan");

    FlashLoanReceiver(flashLoanReceiver).enableRepayExactAmounts(0, expectedRepaymentT1);
    fpmm.swap(loan, 0, address(flashLoanReceiver), "loan");

    assertEq(IERC20(token0).balanceOf(protocolFeeRecipient), 0);
    assertEq(IERC20(token1).balanceOf(protocolFeeRecipient), expectedProtocolFeeT1);
    assertEq(fpmm.reserve0(), beforeReserve0 - loan);
    assertEq(fpmm.reserve1(), beforeReserve1 + scaledLoan + expectedLpFeeT1);
  }

  function test_swap_whenExploitingReentrancy_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.ReentrancyExploiter)
    withOracleRate(1e24, 1e24)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    address attacker = makeAddr("ATTACKER");

    vm.prank(attacker);
    // This should revert due to the ReentrancyGuard in FPMM
    vm.expectRevert("ReentrancyGuard: reentrant call");
    ReentrancyExploiter(flashLoanReceiver).executeFlashLoanAttack(50e18, 0);
  }

  function test_swap_whenPerformingArbitrageToken0ToToken1_shouldGenerateProfit()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupMockExchange(1.2e18) // rate = 1:1.2, 18 decimals
    withOracleRate(1e24, 1e24) // rate = 1:1
    setupFlashLoanReceiver(18, 18, ReceiverType.ArbitrageFlashLoanReceiver)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    vm.prank(owner);
    fpmm.setLPFee(0);

    uint256 flashLoanAmount = 50e18;
    ArbitrageFlashLoanReceiver(flashLoanReceiver).executeArbitrage(true, flashLoanAmount); // Borrow token0

    // Check that the arbitrageur made a profit in token1
    uint256 profit1 = ArbitrageFlashLoanReceiver(flashLoanReceiver).profit1();
    assertGt(profit1, 0, "No profit made in arbitrage");
    uint256 token1FromExchange = (flashLoanAmount * 1.2e18) / 1e18; // 60e18
    uint256 token1ToRepay = flashLoanAmount; // Simplified for test
    uint256 expectedProfit = token1FromExchange - token1ToRepay; // 10e18
    assertEq(profit1, expectedProfit, "Unexpected profit amount");

    assertEq(fpmm.reserve0(), 100_000e18 - 50e18, "Reserve0 should be decreased by loan amount");
    assertEq(fpmm.reserve1(), 200_000e18 + 50e18, "Reserve1 should increase by loan amount");
  }

  function test_swap_whenPerformingArbitrageToken1ToToken0_shouldGenerateProfit()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupMockExchange(0.8e18) // rate = 1:0.8
    withOracleRate(1e24, 1e24) // rate = 1:1
    setupFlashLoanReceiver(18, 18, ReceiverType.ArbitrageFlashLoanReceiver)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    vm.prank(owner);
    fpmm.setLPFee(0);

    uint256 flashLoanAmount = 50e18;
    ArbitrageFlashLoanReceiver(flashLoanReceiver).executeArbitrage(false, flashLoanAmount); // Borrow token1

    uint256 profit0 = ArbitrageFlashLoanReceiver(flashLoanReceiver).profit0();
    assertGt(profit0, 0, "No profit made in arbitrage");

    uint256 token0FromExchange = (flashLoanAmount * 1e18) / 0.8e18; // 62.5e18
    uint256 token0ToRepay = flashLoanAmount; // Simplified for test
    uint256 expectedProfit = token0FromExchange - token0ToRepay; // 12.5e18
    assertEq(profit0, expectedProfit, "Unexpected profit amount");

    assertEq(fpmm.reserve0(), 100_000e18 + flashLoanAmount, "Reserve0 should increase by loan amount");
    assertEq(fpmm.reserve1(), 200_000e18 - flashLoanAmount, "Reserve1 should decrease by loan amount");
  }

  function test_swap_whenMarketConditionsChange_shouldHandleCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupMockExchange(1.2e18)
    withOracleRate(1e24, 1e24) // rate = 1:1
    setupFlashLoanReceiver(18, 18, ReceiverType.ArbitrageFlashLoanReceiver)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    vm.prank(owner);
    fpmm.setLPFee(0);

    // Execute first arbitrage with favorable conditions
    ArbitrageFlashLoanReceiver(flashLoanReceiver).executeArbitrage(true, 50e18); // Borrow token0
    uint256 firstProfit = ArbitrageFlashLoanReceiver(flashLoanReceiver).profit1();
    assertEq(firstProfit, 10e18, "Unexpected profit amount");

    // Change market conditions to make arbitrage unprofitable
    exchange.setExchangeRate(0.9e18); // Now external exchange has worse rate than FPMM

    // Attempt arbitrage with unfavorable conditions
    vm.expectRevert("Arbitrage not profitable");
    ArbitrageFlashLoanReceiver(flashLoanReceiver).executeArbitrage(true, 20e18);

    // Set rate to make token1->token0 arbitrage profitable
    exchange.setExchangeRate(0.5e18); // Now profitable in other direction

    // Execute arbitrage in opposite direction
    ArbitrageFlashLoanReceiver(flashLoanReceiver).executeArbitrage(false, 50e18); // Borrow token1
    uint256 secondProfit = ArbitrageFlashLoanReceiver(flashLoanReceiver).profit0();
    assertEq(secondProfit, 50e18, "Unexpected profit amount");
  }
}
