// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

contract FPMMSwapTest is FPMMBaseTest {
  bytes medianRateCalldata;

  function setUp() public override {
    super.setUp();
    address referenceRateFeedID = makeAddr("REFERENCE_RATE_FEED");
    vm.prank(fpmm.owner());
    fpmm.setReferenceRateFeedID(referenceRateFeedID);
    medianRateCalldata = abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID);
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

  function test_swap_shouldRevert_whenCalledWithInvalidToAddress()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    deal(token0, address(fpmm), 100e18);

    vm.expectRevert("FPMM: INVALID_TO_ADDRESS");
    fpmm.swap(50e18, 0, token0, "");
  }

  function test_swap_shouldRevert_whenInsufficientOutputBasedOnOracle()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    deal(token0, address(this), 100e18);
    IERC20(token0).transfer(address(fpmm), 100e18);

    vm.expectRevert("FPMM: INSUFFICIENT_OUTPUT_BASED_ON_ORACLE");
    fpmm.swap(0, 100e18, address(this), "");
  }

  function test_swap_token0ForToken1() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
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
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    uint256 amount1In = 100e18;
    uint256 amount0Out = 99.7e18;

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(ALICE);
    IERC20(token1).transfer(address(fpmm), amount1In);
    fpmm.swap(amount0Out, 0, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(CHARLIE), amount0Out);

    assertEq(fpmm.reserve0(), initialReserve0 - amount0Out);
    assertEq(fpmm.reserve1(), initialReserve1 + amount1In);
  }

  function test_swap_withDifferentExchangeRate()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(2e18, 1e18));

    // Swap 100 token0 for 199.4 token1 (after 0.3% fee)
    uint256 amount0In = 100e18;
    uint256 amount1Out = 199.4e18;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();
    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);
  }

  function test_swap_withDifferentDecimals()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
  {
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Swap 100 token0 (18 decimals) for 99.7 token1 (6 decimals)
    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e6;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);

    uint256 amount1In = 100e6;
    uint256 amount0Out = 99.7e18;

    vm.startPrank(ALICE);
    IERC20(token1).transfer(address(fpmm), amount1In);
    fpmm.swap(amount0Out, 0, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(CHARLIE), amount0Out);
  }

  function test_swap_withDifferentFees() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    // Change fee to 1%
    vm.prank(fpmm.owner());
    fpmm.setProtocolFee(100);

    uint256 amount0In = 100e18;
    uint256 amount1Out = 99e18;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), amount1Out);

    // Change fee to 0%
    vm.prank(fpmm.owner());
    fpmm.setProtocolFee(0);

    uint256 amount1In = 100e18;
    uint256 amount0Out = 100e18;

    vm.startPrank(ALICE);
    IERC20(token1).transfer(address(fpmm), amount1In);
    fpmm.swap(amount0Out, 0, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(CHARLIE), amount0Out);
  }

  function test_swap_withComplexExchangeRate()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // Mock oracle for 1234:5678 rate
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1234e18, 5678e18));

    uint256 amountIn = 100e18;
    uint256 expectedAmountOut = 21667805565339908418; // (100e18 * 1234e18 / 5678e18) * (997 / 1000)

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amountIn);
    fpmm.swap(0, expectedAmountOut, CHARLIE, "");
    vm.stopPrank();

    assertEq(IERC20(token1).balanceOf(CHARLIE), expectedAmountOut);
  }

  function test_swap_updatesTimestamp() public initializeFPMM_withDecimalTokens(18, 18) mintInitialLiquidity(18, 18) {
    vm.mockCall(sortedOracles, medianRateCalldata, abi.encode(1e18, 1e18));

    uint256 initialTimestamp;
    (, , initialTimestamp) = fpmm.getReserves();

    vm.warp(block.timestamp + 1000);

    uint256 amount0In = 100e18;
    uint256 amount1Out = 99.7e18;

    deal(token0, address(this), amount0In);
    IERC20(token0).transfer(address(fpmm), amount0In);

    fpmm.swap(0, amount1Out, BOB, "");

    uint256 newTimestamp;
    (, , newTimestamp) = fpmm.getReserves();

    assertEq(newTimestamp, block.timestamp);
    assertGt(newTimestamp, initialTimestamp);
  }
}
