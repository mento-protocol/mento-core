// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";

contract FPMMGettersTest is FPMMBaseTest {
  function test_getReserves_shouldReturnZero_beforeAnyMinting() public initializeFPMM_withDecimalTokens(18, 18) {
    (uint256 reserve0, uint256 reserve1, ) = fpmm.getReserves();

    assertEq(reserve0, 0);
    assertEq(reserve1, 0);
  }
  function test_getReserves_shouldReturnCorrectValues()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    uint256 amount0 = 100e18;
    uint256 amount1 = 200e18;

    (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast) = fpmm.getReserves();

    assertEq(reserve0, amount0);
    assertEq(reserve1, amount1);
    assertEq(blockTimestampLast, block.timestamp);
  }

  function test_metadata_shouldReturnCorrectValues()
    public
    initializeFPMM_withDecimalTokens(18, 6)
    mintInitialLiquidity(18, 6)
  {
    (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, address t0, address t1) = fpmm.metadata();

    assertEq(dec0, 1e18);
    assertEq(dec1, 1e6);
    assertEq(r0, 100e18);
    assertEq(r1, 200e6);
    assertEq(t0, token0);
    assertEq(t1, token1);
  }

  function test_tokens_shouldReturnCorrectAddresses() public initializeFPMM_withDecimalTokens(18, 18) {
    (address t0, address t1) = fpmm.tokens();

    assertEq(t0, token0);
    assertEq(t1, token1);
  }
}
