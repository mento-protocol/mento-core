// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";

contract FPMMMintTest is FPMMBaseTest {
  function test_mint_shouldRevert_whenCalledWithLessThanMinLiquidity() public initializeFPMM_withDecimalTokens(18, 18) {
    uint256 amount0 = 1_000;
    uint256 amount1 = 1_000;

    vm.startPrank(ALICE);

    IERC20(token0).transfer(address(fpmm), amount0);
    IERC20(token1).transfer(address(fpmm), amount1);

    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY_MINTED");
    fpmm.mint(address(this));

    vm.stopPrank();
  }

  function test_mint_shouldMintCorrectAmountOfTokens_whenTotalSupplyIsZero()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    uint256 amount0 = 100e18;
    uint256 amount1 = 200e18;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0);
    IERC20(token1).transfer(address(fpmm), amount1);

    uint256 liquidity = fpmm.mint(ALICE);
    // sqrt(100e18 * 200e18) = 141421356237309504880
    uint256 expectedLiquidity = 141421356237309504880 - fpmm.MINIMUM_LIQUIDITY();
    assertEq(liquidity, expectedLiquidity);
    assertEq(fpmm.balanceOf(ALICE), expectedLiquidity);
    assertEq(fpmm.balanceOf(address(1)), fpmm.MINIMUM_LIQUIDITY());
    assertEq(fpmm.totalSupply(), expectedLiquidity + fpmm.MINIMUM_LIQUIDITY());

    assertEq(fpmm.reserve0(), amount0);
    assertEq(fpmm.reserve1(), amount1);

    vm.stopPrank();
  }

  function test_mint_shouldMintCorrectAmountOfTokens_whenTotalSupplyIsZeroAndDecimalsAreDifferent()
    public
    initializeFPMM_withDecimalTokens(18, 6)
  {
    uint256 amount0 = 100e18;
    uint256 amount1 = 200e6;

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), amount0);
    IERC20(token1).transfer(address(fpmm), amount1);

    uint256 liquidity = fpmm.mint(ALICE);
    // sqrt(100e18 * 200e6) = 141421356237309
    uint256 expectedLiquidity = 141421356237309 - fpmm.MINIMUM_LIQUIDITY();
    assertEq(liquidity, expectedLiquidity);
    assertEq(fpmm.balanceOf(ALICE), expectedLiquidity);
    assertEq(fpmm.balanceOf(address(1)), fpmm.MINIMUM_LIQUIDITY());
    assertEq(fpmm.totalSupply(), expectedLiquidity + fpmm.MINIMUM_LIQUIDITY());

    assertEq(fpmm.reserve0(), amount0);
    assertEq(fpmm.reserve1(), amount1);

    vm.stopPrank();
  }

  function test_mint_shouldWork_whenTotalSupplyIsNotZero()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 amount0 = 50e18;
    uint256 amount1 = 100e18;

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), amount0);
    IERC20(token1).transfer(address(fpmm), amount1);

    uint256 liquidity = fpmm.mint(BOB);
    uint256 expectedLiquidity = 141421356237309504880 / 2; // half of the initial liquidity
    assertEq(liquidity, expectedLiquidity);
    assertEq(fpmm.balanceOf(BOB), expectedLiquidity);
    assertEq(fpmm.totalSupply(), 3 * expectedLiquidity);

    assertEq(fpmm.reserve0(), initialReserve0 + amount0);
    assertEq(fpmm.reserve1(), initialReserve1 + amount1);

    vm.stopPrank();
  }

  function test_mint_shouldWork_whenDecimalsAreDifferent()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
  {
    uint256 amount0 = 50e18;
    uint256 amount1 = 100e6;

    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialReserve1 = fpmm.reserve1();

    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), amount0);
    IERC20(token1).transfer(address(fpmm), amount1);

    uint256 liquidity = fpmm.mint(BOB);
    uint256 expectedLiquidity = uint256(141421356237309) / 2; // half of the initial liquidity
    assertEq(liquidity, expectedLiquidity);
    assertEq(fpmm.balanceOf(BOB), expectedLiquidity);
    assertApproxEqRel(fpmm.totalSupply(), 3 * expectedLiquidity, 1e6);

    assertEq(fpmm.reserve0(), initialReserve0 + amount0);
    assertEq(fpmm.reserve1(), initialReserve1 + amount1);

    vm.stopPrank();
  }

  function test_mint_shouldUseToken0AsLimitingFactor()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 initialReserve0 = fpmm.reserve0();
    uint256 initialTotalSupply = fpmm.totalSupply();

    // Add less token0 in proportion to token1
    uint256 amount0 = 25e18; // 25% of initial reserve0
    uint256 amount1 = 100e18; // 50% of initial reserve1

    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), amount0);
    IERC20(token1).transfer(address(fpmm), amount1);

    uint256 liquidity = fpmm.mint(BOB);
    uint256 expectedLiquidity = (amount0 * initialTotalSupply) / initialReserve0;

    assertEq(liquidity, expectedLiquidity);
    assertEq(fpmm.balanceOf(BOB), expectedLiquidity);

    vm.stopPrank();
  }

  function test_mint_shouldUseToken1AsLimitingFactor()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 initialReserve1 = fpmm.reserve1();
    uint256 initialTotalSupply = fpmm.totalSupply();

    // Add less token1 in proportion to token0
    uint256 amount0 = 100e18; // 100% of initial reserve0
    uint256 amount1 = 50e18; // 25% of initial reserve1

    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), amount0);
    IERC20(token1).transfer(address(fpmm), amount1);

    uint256 liquidity = fpmm.mint(BOB);
    uint256 expectedLiquidity = (amount1 * initialTotalSupply) / initialReserve1;

    assertEq(liquidity, expectedLiquidity);
    assertEq(fpmm.balanceOf(BOB), expectedLiquidity);

    vm.stopPrank();
  }

  function test_mint_shouldWorkCorrectly_withMultipleMints()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // First mint by BOB
    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), 50e18);
    IERC20(token1).transfer(address(fpmm), 100e18);
    fpmm.mint(BOB);
    vm.stopPrank();

    // Second mint by ALICE
    uint256 totalSupplyAfterBobMint = fpmm.totalSupply();
    uint256 reserveAfterBobMint0 = fpmm.reserve0();
    uint256 reserveAfterBobMint1 = fpmm.reserve1();

    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), 75e18);
    IERC20(token1).transfer(address(fpmm), 150e18);
    uint256 liquidityAlice2 = fpmm.mint(ALICE);
    vm.stopPrank();

    uint256 expectedAliceLiquidity = (75e18 * totalSupplyAfterBobMint) / reserveAfterBobMint0;

    assertEq(liquidityAlice2, expectedAliceLiquidity);
    assertEq(fpmm.reserve0(), reserveAfterBobMint0 + 75e18);
    assertEq(fpmm.reserve1(), reserveAfterBobMint1 + 150e18);
  }

  function test_mint_shouldSetCorrectRecipient() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), 100e18);
    IERC20(token1).transfer(address(fpmm), 200e18);

    uint256 liquidity = fpmm.mint(BOB);
    vm.stopPrank();

    assertEq(fpmm.balanceOf(ALICE), 0);
    assertEq(fpmm.balanceOf(BOB), liquidity);
  }

  function test_mint_shouldUpdateTimestamp_whenReservesChange()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 initialTimestamp;
    (, , initialTimestamp) = fpmm.getReserves();

    vm.warp(block.timestamp + 100);

    vm.startPrank(BOB);
    IERC20(token0).transfer(address(fpmm), 10e18);
    IERC20(token1).transfer(address(fpmm), 20e18);
    fpmm.mint(BOB);
    vm.stopPrank();

    uint256 newTimestamp;
    (, , newTimestamp) = fpmm.getReserves();

    assertEq(newTimestamp, block.timestamp);
    assertGt(newTimestamp, initialTimestamp);
  }
}
