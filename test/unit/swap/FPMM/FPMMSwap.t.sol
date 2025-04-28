// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

contract FPMMSwapTest is FPMMBaseTest {
  address public referenceRateFeedID;

  function setUp() public override {
    super.setUp();
    referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);
  }

  function test_swap_shouldRevert_whenCalledWith0AmountOut() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.expectRevert("FPMM: INSUFFICIENT_OUTPUT_AMOUNT");
    fpmm.swap(0, 0, address(this), "");
  }

  function test_swap_shouldRevert_whenCalledWithInsufficientLiquidity()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY");
    fpmm.swap(100e18, 0, address(this), "");
  }

  function test_swap_shouldRevert_whenCalledWithInvalidDirection()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    deal(token0, address(fpmm), 100e18);

    vm.expectRevert("FPMM: INVALID_SWAP_DIRECTION");
    fpmm.swap(50e18, 0, address(this), "");
  }

  function test_swap_shouldRevert_whenInsufficientOutputBasedOnOracle()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Try to swap 100 token0 for 100 token1 (should be rejected because of fee)
    deal(token0, address(this), 100e18);
    IERC20(token0).transfer(address(fpmm), 100e18);

    vm.expectRevert("FPMM: INSUFFICIENT_OUTPUT_BASED_ON_ORACLE");
    fpmm.swap(0, 100e18, address(this), "");
  }

  function test_swap_token0ForToken1() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e18;

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);

    assertEq(fpmm.reserve0(), initialReserve0 + amount0In);
    assertEq(fpmm.reserve1(), initialReserve1 - amount1Out);
  }

  function test_swap_token1ForToken0() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 1:1 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Swap 100 token1 for 99.7 token0 (after 0.3% fee)
    uint256 amount1In = 100e18;
    uint256 amount0Out = 99.7e18;

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    deal(token1, address(this), amount1In);
    IERC20(token1).transfer(address(fpmm), amount1In);

    fpmm.swap(amount0Out, 0, BOB, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token0).balanceOf(BOB), amount0Out);

    // Verify reserves updated correctly
    assertEq(fpmm.reserve0(), initialReserve0 - amount0Out);
    assertEq(fpmm.reserve1(), initialReserve1 + amount1In);
  }

  function test_swap_withDifferentExchangeRate()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 2:1 rate (2 token1 for 1 token0)
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(2e18, 1e18));

    // Swap 100 token0 for 199.4 token1 (after 0.3% fee)
    uint256 amount0In = 100e18;
    uint256 amount1Out = 199.4e18;

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, BOB, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token1).balanceOf(BOB), amount1Out);
  }

  function test_swap_withDifferentDecimals()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
  {
    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 1:1 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Swap 100 token0 (18 decimals) for 99.7 token1 (6 decimals)
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e6;

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, BOB, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token1).balanceOf(BOB), amount1Out);

    // Now swap in the other direction
    // Swap 100 token1 (6 decimals) for 99.7 token0 (18 decimals)
    uint256 amount1In = 100e6;
    uint256 amount0Out = 99.7e18;

    deal(token1, address(this), amount1In);
    IERC20(token1).transfer(address(fpmm), amount1In);

    fpmm.swap(amount0Out, 0, ALICE, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token0).balanceOf(ALICE), amount0Out);
  }

  function test_swap_withDifferentFees() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 1:1 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Change fee to 1%
    vm.prank(fpmm.owner());
    fpmm.setProtocolFee(100); // 100 basis points = 1%

    // Swap 100 token0 for 99 token1 (after 1% fee)
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99e18;

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, BOB, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token1).balanceOf(BOB), amount1Out);

    // Change fee to 0%
    vm.prank(fpmm.owner());
    fpmm.setProtocolFee(0);

    // Swap 100 token0 for 100 token1 (no fee)
    amount0In = 100e18;
    amount1Out = 100e18;

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, ALICE, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token1).balanceOf(ALICE), amount1Out);
  }

  function test_swap_withComplexExchangeRate()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 1234:5678 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1234e18, 5678e18));

    uint256 amountIn = 1000e18;

    // Calculate expected amount out based on the complex rate
    // token0 to token1: (1000 * 0.997) * (1234/5678)
    uint256 expectedAmountOut = 216678055653399084184; // (1000e18 * 1234e18 / 5678e18) * (997 / 1000)

    deal(token0, address(this), amountIn);
    IERC20(token0).transfer(address(fpmm), amountIn);

    fpmm.swap(0, expectedAmountOut, BOB, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token1).balanceOf(BOB), expectedAmountOut);
  }

  function test_swap_updatesTimestamp() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 1:1 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    uint256 initialTimestamp;
    (, , initialTimestamp) = fpmm.getReserves();

    // Move time forward
    vm.warp(block.timestamp + 1000);

    // Perform a swap
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e18;

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, BOB, "");

    uint256 newTimestamp;
    (, , newTimestamp) = fpmm.getReserves();

    // Verify timestamp was updated
    assertEq(newTimestamp, block.timestamp);
    assertGt(newTimestamp, initialTimestamp);
  }

  function test_swap_withLargeAmounts() public initializeFPMM_withDecimalTokens(18, 18) {
    // Add large initial liquidity
    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), 1_000_000e18);
    IERC20(token1).transfer(address(fpmm), 2_000_000e18);
    fpmm.mint(ALICE);
    vm.stopPrank();

    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 1:1 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Swap large amount
    uint256 amount0In = 500_000e18;
    uint256 amount1Out = 498_500e18; // 500,000 - 0.3% fee = 498,500

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, BOB, "");

    // Verify receiver got the tokens
    assertEq(IERC20(token1).balanceOf(BOB), amount1Out);
  }

  function test_swap_swapToSenderAddress()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // Set reference rate feed
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);

    // Mock oracle for 1:1 rate
    bytes memory medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Swap 100 token0 for 99.7 token1 (after 0.3% fee), but send to self
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e18;
    address sender = address(this);

    deal(token0, sender, amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    uint256 balanceBefore = IERC20(token1).balanceOf(sender);

    fpmm.swap(0, amount1Out, sender, "");

    // Verify sender got the tokens
    assertEq(IERC20(token1).balanceOf(sender), balanceBefore + amount1Out);
  }
}
