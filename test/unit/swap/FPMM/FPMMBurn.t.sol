// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

contract FPMMBurnTest is FPMMBaseTest {
  event Burn(address indexed sender, uint256 amount0, uint256 amount1, uint256 liquidity, address indexed to);
  function test_burn_whenNoLiquidityInPool_shouldRevert()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // Call burn without transferring any LP tokens to the pool
    vm.expectRevert(IFPMM.InsufficientLiquidityBurned.selector);
    fpmm.burn(BOB);
  }

  function test_burn_whenTokensProvided_shouldTransferWithCorrectProportions()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 liquidity = fpmm.balanceOf(ALICE) / 2; // Burn half of Alice's liquidity
    uint256 totalSupply = fpmm.totalSupply();
    uint256 reserve0 = fpmm.reserve0();
    uint256 reserve1 = fpmm.reserve1();

    uint256 expectedAmount0 = (liquidity * reserve0) / totalSupply;
    uint256 expectedAmount1 = (liquidity * reserve1) / totalSupply;

    uint256 initialAliceBalance0 = IERC20(token0).balanceOf(ALICE);
    uint256 initialAliceBalance1 = IERC20(token1).balanceOf(ALICE);

    vm.startPrank(ALICE);
    fpmm.transfer(address(fpmm), liquidity);

    (uint256 amount0, uint256 amount1) = fpmm.burn(ALICE);
    vm.stopPrank();

    assertEq(amount0, expectedAmount0);
    assertEq(amount1, expectedAmount1);

    assertEq(IERC20(token0).balanceOf(ALICE), initialAliceBalance0 + expectedAmount0);
    assertEq(IERC20(token1).balanceOf(ALICE), initialAliceBalance1 + expectedAmount1);

    assertEq(fpmm.balanceOf(address(fpmm)), 0);
    assertEq(fpmm.totalSupply(), totalSupply - liquidity);

    assertEq(fpmm.reserve0(), reserve0 - expectedAmount0);
    assertEq(fpmm.reserve1(), reserve1 - expectedAmount1);
  }

  function test_burn_whenExecuted_shouldUpdateTimestamp()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 initialTimestamp;
    (, , initialTimestamp) = fpmm.getReserves();

    vm.warp(block.timestamp + 100);

    vm.startPrank(ALICE);
    uint256 liquidity = fpmm.balanceOf(ALICE) / 2;
    fpmm.transfer(address(fpmm), liquidity);
    fpmm.burn(ALICE);
    vm.stopPrank();

    uint256 newTimestamp;
    (, , newTimestamp) = fpmm.getReserves();

    assertEq(newTimestamp, block.timestamp);
    assertGt(newTimestamp, initialTimestamp);
  }

  function test_burn_whenDifferentDecimals_shouldWorkCorrectly()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
  {
    uint256 liquidity = fpmm.balanceOf(ALICE) / 4; // Burn 25% of Alice's liquidity
    uint256 totalSupply = fpmm.totalSupply();
    uint256 reserve0 = fpmm.reserve0();
    uint256 reserve1 = fpmm.reserve1();

    uint256 expectedAmount0 = (liquidity * reserve0) / totalSupply;
    uint256 expectedAmount1 = (liquidity * reserve1) / totalSupply;

    vm.startPrank(ALICE);
    fpmm.transfer(address(fpmm), liquidity);

    (uint256 amount0, uint256 amount1) = fpmm.burn(ALICE);
    vm.stopPrank();

    assertEq(amount0, expectedAmount0);
    assertEq(amount1, expectedAmount1);

    assertEq(fpmm.reserve0(), reserve0 - expectedAmount0);
    assertEq(fpmm.reserve1(), reserve1 - expectedAmount1);
  }

  function test_burn_whenSpecifiedRecipient_shouldTransferTokens()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 initialBobBalance0 = IERC20(token0).balanceOf(BOB);
    uint256 initialBobBalance1 = IERC20(token1).balanceOf(BOB);

    uint256 liquidity = fpmm.balanceOf(ALICE) / 2;
    uint256 totalSupply = fpmm.totalSupply();
    uint256 reserve0 = fpmm.reserve0();
    uint256 reserve1 = fpmm.reserve1();

    uint256 expectedAmount0 = (liquidity * reserve0) / totalSupply;
    uint256 expectedAmount1 = (liquidity * reserve1) / totalSupply;

    vm.startPrank(ALICE);
    fpmm.transfer(address(fpmm), liquidity);
    (uint256 amount0, uint256 amount1) = fpmm.burn(BOB);
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(BOB), initialBobBalance0 + expectedAmount0);
    assertEq(IERC20(token1).balanceOf(BOB), initialBobBalance1 + expectedAmount1);

    assertEq(amount0, expectedAmount0);
    assertEq(amount1, expectedAmount1);
  }

  function test_burn_whenOneReserveIsSmallAndLiquidityFractionRoundsDown_shouldTransferOtherToken()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
    withOracleRate(1e18, 1e18)
    withFXMarketOpen(true)
    withRecentRate(true)
  {
    // leave only 1 wei of token1 in the pool
    uint256 amount0In = (200e18 * 10_000) / uint256(10_000 - 30);
    uint256 amount1Out = fpmm.getAmountOut(amount0In, token0);

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0In);
    fpmm.swap(0, amount1Out, ALICE, "");
    vm.stopPrank();

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();
    assertEq(initialReserve1, 1);

    uint256 liquidity = fpmm.balanceOf(ALICE);
    uint256 totalSupply = fpmm.totalSupply();

    vm.startPrank(ALICE);
    fpmm.transfer(address(fpmm), liquidity);
    (uint256 amount0, uint256 amount1) = fpmm.burn(ALICE);
    vm.stopPrank();

    assertEq(amount0, (liquidity * initialReserve0) / totalSupply);
    assertEq(amount1, 0);

    uint256 newReserve0 = fpmm.reserve0();
    uint256 newReserve1 = fpmm.reserve1();
    // allow for 1 wei of error due to rounding
    // reminder in reserves is equal to the MINIMUM_LIQUIDITY share of the total supply
    assertApproxEqAbs(newReserve0, (initialReserve0 * fpmm.MINIMUM_LIQUIDITY()) / totalSupply, 1);
    assertEq(newReserve1, 1);
  }

  function test_burn_whenMultipleLPHolders_shouldBurnCorrectAmount()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), 50e18);
    IERC20(token1).transfer(address(fpmm), 100e18);
    uint256 bobLiquidity = fpmm.mint(BOB);
    vm.stopPrank();

    uint256 initialBobBalance0 = IERC20(token0).balanceOf(BOB);
    uint256 initialBobBalance1 = IERC20(token1).balanceOf(BOB);

    uint256 initialAliceBalance0 = IERC20(token0).balanceOf(ALICE);
    uint256 initialAliceBalance1 = IERC20(token1).balanceOf(ALICE);

    uint256 aliceLiquidity = fpmm.balanceOf(ALICE) / 2; // Burn half of Alice's liquidity
    uint256 totalSupply = fpmm.totalSupply();
    uint256 reserve0 = fpmm.reserve0();
    uint256 reserve1 = fpmm.reserve1();

    uint256 expectedAmount0 = (aliceLiquidity * reserve0) / totalSupply;
    uint256 expectedAmount1 = (aliceLiquidity * reserve1) / totalSupply;

    vm.startPrank(ALICE);
    fpmm.transfer(address(fpmm), aliceLiquidity);
    vm.expectEmit(true, true, true, true);
    emit Burn(ALICE, expectedAmount0, expectedAmount1, aliceLiquidity, ALICE);
    (uint256 amount0, uint256 amount1) = fpmm.burn(ALICE);
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(ALICE), initialAliceBalance0 + expectedAmount0);
    assertEq(IERC20(token1).balanceOf(ALICE), initialAliceBalance1 + expectedAmount1);

    assertEq(amount0, expectedAmount0);
    assertEq(amount1, expectedAmount1);

    assertEq(fpmm.reserve0(), reserve0 - expectedAmount0);
    assertEq(fpmm.reserve1(), reserve1 - expectedAmount1);

    vm.startPrank(BOB);
    fpmm.transfer(address(fpmm), bobLiquidity); // Bob's liquidity should be half of the Alice's initial liquidity
    (amount0, amount1) = fpmm.burn(BOB);
    vm.stopPrank();

    assertApproxEqAbs(IERC20(token0).balanceOf(BOB), initialBobBalance0 + expectedAmount0, 1e3);
    assertApproxEqAbs(IERC20(token1).balanceOf(BOB), initialBobBalance1 + expectedAmount1, 1e3);

    assertApproxEqAbs(amount0, expectedAmount0, 1e3);
    assertApproxEqAbs(amount1, expectedAmount1, 1e3);

    assertApproxEqAbs(fpmm.reserve0(), reserve0 - 2 * expectedAmount0, 1e3);
    assertApproxEqAbs(fpmm.reserve1(), reserve1 - 2 * expectedAmount1, 1e3);
  }
}
