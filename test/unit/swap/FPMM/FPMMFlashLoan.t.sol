// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { FlashLoanReceiver } from "./helpers/FlashLoanReceiver.sol";
import { ReentrancyExploiter } from "./helpers/ReentrancyExploiter.sol";
import { MockExchange } from "./helpers/MockExchange.sol";
import { ArbitrageFlashLoanReceiver } from "./helpers/ArbitrageFlashLoanReceiver.sol";

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

  function test_flashLoan_token0_success()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    uint256 flashLoanAmount = 50e18;
    bytes memory customData = abi.encode("Custom flash loan data");

    uint256 swapFee = (flashLoanAmount * 31) / 10000;

    // Set to repay with extra fee
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, swapFee);

    fpmm.swap(flashLoanAmount, 0, address(flashLoanReceiver), customData);

    assertEq(FlashLoanReceiver(flashLoanReceiver).sender(), address(this));
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), flashLoanAmount);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), 0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).receivedData(), customData);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100e18 + swapFee); // Initial 100e18 + fee
    assertEq(fpmm.reserve1(), 200e18); // Unchanged
  }

  function test_flashLoan_token1_success()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    uint256 flashLoanAmount = 50e18;
    bytes memory customData = abi.encode("Custom flash loan data");

    uint256 swapFee = (flashLoanAmount * 31) / 10000;

    // Set to repay with extra fee
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, swapFee);

    fpmm.swap(0, flashLoanAmount, flashLoanReceiver, customData);

    assertEq(FlashLoanReceiver(flashLoanReceiver).sender(), address(this));
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), 0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), flashLoanAmount);
    assertEq(FlashLoanReceiver(flashLoanReceiver).receivedData(), customData);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100e18); // Unchanged
    assertEq(fpmm.reserve1(), 200e18 + swapFee); // Initial 200e18 + fee
  }

  function test_flashLoan_bothTokens_success()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    uint256 flashLoanAmount0 = 30e18;
    uint256 flashLoanAmount1 = 40e18;
    bytes memory customData = abi.encode("Custom flash loan data");

    uint256 swapFee = (flashLoanAmount1 * 31) / 10000;

    // Set to repay with extra fee
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, swapFee);

    fpmm.swap(flashLoanAmount0, flashLoanAmount1, address(flashLoanReceiver), customData);

    assertEq(FlashLoanReceiver(flashLoanReceiver).sender(), address(this));
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), flashLoanAmount0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), flashLoanAmount1);
    assertEq(FlashLoanReceiver(flashLoanReceiver).receivedData(), customData);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100e18 + swapFee); // Initial 100e18 + fee
    assertEq(fpmm.reserve1(), 200e18 + swapFee); // Initial 200e18 + fee
  }

  function test_flashLoan_failsWhenNotRepaid()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    uint256 flashLoanAmount = 50e18;

    // Set NOT to repay
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(false, 0);

    // Flash loan should fail because it's not repaid
    vm.expectRevert("FPMM: INSUFFICIENT_INPUT_AMOUNT");
    fpmm.swap(flashLoanAmount, 0, address(flashLoanReceiver), "data");
  }

  function test_flashLoan_failsWhenPaidLessThanRequired()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    uint256 flashLoanAmount = 50e18;
    uint256 lessThanRequiredFee = (flashLoanAmount * 20) / 10000;

    // Pay back less than required
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, lessThanRequiredFee);

    // Flash loan should fail because it's not repaid correctly
    vm.expectRevert("FPMM: RESERVE_VALUE_DECREASED");
    fpmm.swap(flashLoanAmount, 0, address(flashLoanReceiver), "data");
  }

  function test_flashLoan_failsWhenReceiverReverts()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    uint256 flashLoanAmount = 50e18;

    // Make the receiver revert in the hook
    FlashLoanReceiver(flashLoanReceiver).setRevertInHook(true);

    // Flash loan should fail because the receiver reverts
    vm.expectRevert("FlashLoanReceiver: Reverting as requested");
    fpmm.swap(flashLoanAmount, 0, flashLoanReceiver, "data");
  }

  function test_flashLoan_maxAmounts()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    // Try to flash loan the maximum amount
    // Try to flash loan the maximum amount
    uint256 maxToken0Amount = fpmm.reserve0() - 1;
    uint256 maxToken1Amount = fpmm.reserve1() - 1;

    // Ensure the flash loan receiver has enough tokens to repay
    deal(token0, flashLoanReceiver, maxToken0Amount + 1e18);
    deal(token1, flashLoanReceiver, maxToken1Amount + 1e18);

    // Set to repay with extra fee (simplified to 1e18 for test)
    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, 1e18);

    fpmm.swap(maxToken0Amount, maxToken1Amount, flashLoanReceiver, "Max flash loan test");

    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), maxToken0Amount);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), maxToken1Amount);

    // Verify FPMM reserves increased by the extra repaid amount
    assertEq(fpmm.reserve0(), 100e18 + 1e18); // Initial + fee
    assertEq(fpmm.reserve1(), 200e18 + 1e18); // Initial + fee
  }

  function test_flashLoan_withDifferentDecimals()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
    setupFlashLoanReceiver(18, 6, ReceiverType.FlashLoanReceiver)
    setupMockOracleRate(1e18, 1e18)
  {
    // Set protocol fee to 0 for easier testing
    fpmm.setProtocolFee(0);

    uint256 flashLoanAmount0 = 30e18; // 18 decimals
    uint256 flashLoanAmount1 = 40e6; // 6 decimals

    FlashLoanReceiver(flashLoanReceiver).setRepayBehavior(true, 0);

    fpmm.swap(flashLoanAmount0, flashLoanAmount1, flashLoanReceiver, "Different decimals");

    assertEq(FlashLoanReceiver(flashLoanReceiver).amount0Received(), flashLoanAmount0);
    assertEq(FlashLoanReceiver(flashLoanReceiver).amount1Received(), flashLoanAmount1);
  }

  function test_flashLoan_reentrancy()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupFlashLoanReceiver(18, 18, ReceiverType.ReentrancyExploiter)
    setupMockOracleRate(1e18, 1e18)
  {
    address attacker = makeAddr("ATTACKER");

    vm.prank(attacker);
    // This should revert due to the ReentrancyGuard in FPMM
    vm.expectRevert("ReentrancyGuard: reentrant call");
    ReentrancyExploiter(flashLoanReceiver).executeFlashLoanAttack(50e18, 0);
  }

  function test_flashLoan_realArbitrageScenario()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupMockExchange(1.2e18) // rate = 1:1.2
    setupMockOracleRate(1e18, 1e18) // rate = 1:1
    setupFlashLoanReceiver(18, 18, ReceiverType.ArbitrageFlashLoanReceiver)
  {
    fpmm.setProtocolFee(0);

    uint256 flashLoanAmount = 50e18;
    ArbitrageFlashLoanReceiver(flashLoanReceiver).executeArbitrage(true, flashLoanAmount); // Borrow token0

    // Check that the arbitrageur made a profit in token1
    uint256 profit1 = ArbitrageFlashLoanReceiver(flashLoanReceiver).profit1();
    assertGt(profit1, 0, "No profit made in arbitrage");
    uint256 token1FromExchange = (flashLoanAmount * 1.2e18) / 1e18; // 60e18
    uint256 token1ToRepay = flashLoanAmount; // Simplified for test
    uint256 expectedProfit = token1FromExchange - token1ToRepay; // 10e18
    assertEq(profit1, expectedProfit, "Unexpected profit amount");

    assertEq(fpmm.reserve0(), 100e18 - 50e18, "Reserve0 should be decreased by loan amount");
    assertEq(fpmm.reserve1(), 200e18 + 50e18, "Reserve1 should increase by loan amount");
  }

  function test_flashLoan_arbitrageWithReverseRates()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupMockExchange(0.8e18) // rate = 1:0.8
    setupMockOracleRate(1e18, 1e18) // rate = 1:1
    setupFlashLoanReceiver(18, 18, ReceiverType.ArbitrageFlashLoanReceiver)
  {
    fpmm.setProtocolFee(0);

    uint256 flashLoanAmount = 50e18;
    ArbitrageFlashLoanReceiver(flashLoanReceiver).executeArbitrage(false, flashLoanAmount); // Borrow token1

    uint256 profit0 = ArbitrageFlashLoanReceiver(flashLoanReceiver).profit0();
    assertGt(profit0, 0, "No profit made in arbitrage");

    uint256 token0FromExchange = (flashLoanAmount * 1e18) / 0.8e18; // 62.5e18
    uint256 token0ToRepay = flashLoanAmount; // Simplified for test
    uint256 expectedProfit = token0FromExchange - token0ToRepay; // 12.5e18
    assertEq(profit0, expectedProfit, "Unexpected profit amount");

    assertEq(fpmm.reserve0(), 100e18 + flashLoanAmount, "Reserve0 should increase by loan amount");
    assertEq(fpmm.reserve1(), 200e18 - flashLoanAmount, "Reserve1 should decrease by loan amount");
  }

  function test_flashLoan_arbitrageWithChangingMarketConditions()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    setupMockExchange(1.2e18)
    setupMockOracleRate(1e18, 1e18) // rate = 1:1
    setupFlashLoanReceiver(18, 18, ReceiverType.ArbitrageFlashLoanReceiver)
  {
    fpmm.setProtocolFee(0);

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
