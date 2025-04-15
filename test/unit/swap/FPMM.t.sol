// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable modifier-name-mixedcase,
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";

import { FPMM } from "contracts/swap/FPMM.sol";
import { ERC20DecimalsMock } from "openzeppelin-contracts-next/contracts/mocks/ERC20DecimalsMock.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
contract FPMMTest is Test {
  FPMM public fpmm;

  address public token0;
  address public token1;

  address public ALICE = makeAddr("ALICE");
  address public BOB = makeAddr("BOB");

  function setUp() public {
    fpmm = new FPMM(false);
  }

  modifier initializeFPMM_withDecimalTokens(uint8 decimals0, uint8 decimals1) {
    token0 = address(new ERC20DecimalsMock("token0", "T0", decimals0));
    token1 = address(new ERC20DecimalsMock("token1", "T1", decimals1));

    fpmm.initialize(token0, token1);

    deal(token0, ALICE, 1_000 * 10 ** decimals0);
    deal(token1, ALICE, 1_000 * 10 ** decimals1);
    deal(token0, BOB, 1_000 * 10 ** decimals0);
    deal(token1, BOB, 1_000 * 10 ** decimals1);

    _;
  }

  function test_initialize_shouldInitWithCorrectValues() public initializeFPMM_withDecimalTokens(18, 18) {
    assertEq(fpmm.symbol(), "FPMM-T0/T1");
    assertEq(fpmm.name(), "Mento Fixed Price MM - T0/T1");
    assertEq(fpmm.decimals(), 18);
    assertEq(fpmm.owner(), address(this));

    assertEq(fpmm.token0(), token0);
    assertEq(fpmm.token1(), token1);
    assertEq(fpmm.decimals0(), 1e18);
    assertEq(fpmm.decimals1(), 1e18);
  }

  function test_initialize_shouldRevertIfCalledTwice() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.expectRevert("Initializable: contract is already initialized");
    fpmm.initialize(token0, token1);
  }

  function test_initialize_shouldSetCorrectDecimals_withDifferentDecimals()
    public
    initializeFPMM_withDecimalTokens(6, 12)
  {
    assertEq(fpmm.decimals0(), 1e6);
    assertEq(fpmm.decimals1(), 1e12);
  }

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
}
