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

  modifier mintInitialLiquidity(uint8 decimals0, uint8 decimals1) {
    vm.startPrank(ALICE);
    IERC20(token0).transfer(address(fpmm), 100 * 10 ** decimals0);
    IERC20(token1).transfer(address(fpmm), 200 * 10 ** decimals1);
    fpmm.mint(ALICE);
    vm.stopPrank();

    _;
  }

  function test_constructor_shouldDisableInitializers_whenParameterIsTrue() public {
    FPMM fpmmDisabled = new FPMM(true);

    vm.expectRevert("Initializable: contract is already initialized");
    fpmmDisabled.initialize(address(0), address(0));
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

  function test_getReserves_shouldReturnZero_beforeAnyMinting() public initializeFPMM_withDecimalTokens(18, 18) {
    (uint256 reserve0, uint256 reserve1, ) = fpmm.getReserves();

    assertEq(reserve0, 0);
    assertEq(reserve1, 0);
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

  function test_burn_shouldRevert_whenNoLiquidityInPool()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // Call burn without transferring any LP tokens to the pool
    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY_BURNED");
    fpmm.burn(BOB);
  }

  function test_burn_shouldTransferTokens_withCorrectProportions()
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

  function test_burn_shouldUpdateTimestamp()
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

  function test_burn_shouldWork_withDifferentDecimals()
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

  function test_burn_shouldTransferTokens_toSpecifiedRecipient()
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

  function test_burn_shouldRevert_withZeroTokens()
    public
    initializeFPMM_withDecimalTokens(18, 18)
    mintInitialLiquidity(18, 18)
  {
    // Try to burn a tiny amount of LP tokens that would result in 0 token0 or token1
    uint256 tinyLiquidity = 1;

    vm.startPrank(ALICE);
    fpmm.transfer(address(fpmm), tinyLiquidity);

    vm.expectRevert("FPMM: INSUFFICIENT_LIQUIDITY_BURNED");
    fpmm.burn(ALICE);
    vm.stopPrank();
  }

  function test_burn_shouldBurnCorrectAmount_forMultipleLPHolders()
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
