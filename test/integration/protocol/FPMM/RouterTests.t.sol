// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

// Interfaces
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";

// Base integration
import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";

/**
 * @title RouterTests
 * @notice Core tests for Router functionality including setup, pool management, liquidity operations, swaps
 */
contract RouterTests is FPMMBaseIntegration {
  // ============ STATE VARIABLES ============

  // ============ SETUP ============

  function setUp() public override {
    super.setUp();
  }

  // ============ SETUP TESTS ============

  function test_setUp_whenContractsDeployed_shouldConfigureRouterCorrectly() public view {
    // Verify factory configuration
    assertEq(router.factoryRegistry(), address(factoryRegistry));
    assertEq(router.defaultFactory(), address(factory));
  }

  // ============ POOL MANAGEMENT TESTS ============

  function test_poolFor_whenPoolExists_shouldReturnCorrectPoolAddress() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));

    // Test forward order
    address pool = router.poolFor(address(tokenA), address(tokenB), address(0));
    assertEq(pool, fpmm);

    // Test reversed order
    address poolReversed = router.poolFor(address(tokenB), address(tokenA), address(0));
    assertEq(poolReversed, fpmm);
  }

  function test_sortTokens_whenDifferentTokensProvided_shouldSortByAddress() public view {
    address _token0 = address(0x0000000000000000000000000000000000000011);
    address _token1 = address(0x0000000000000000000000000000000000000022);

    // Test forward order
    (address token0, address token1) = router.sortTokens(_token0, _token1);
    assertEq(token0, _token0);
    assertEq(token1, _token1);

    // Test reversed order
    (token0, token1) = router.sortTokens(_token1, _token0);
    assertEq(token0, _token0);
    assertEq(token1, _token1);
  }

  function test_sortTokens_whenSameTokensProvided_shouldRevert() public {
    vm.expectRevert(IRouter.SameAddresses.selector);
    router.sortTokens(address(tokenA), address(tokenA));
  }

  function test_sortTokens_whenZeroAddressProvided_shouldRevert() public {
    vm.expectRevert(IRouter.ZeroAddress.selector);
    router.sortTokens(address(0), address(tokenA));
  }

  // ============ AMOUNT CALCULATION TESTS ============

  function test_getAmountsOut_whenTokenAIsToken0AndOracleRateIs1_shouldCalculateCorrectAmounts() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    uint256 amountIn = 10e18;
    uint256 amountOutExpected = (10e18 * 997) / 1000; // .3% fee

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = _createRoute(address(tokenA), address(tokenB));

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    assertEq(amounts[1], amountOutExpected);
  }

  function test_getAmountsOut_whenTokenBIsToken0AndOracleRateIs2_shouldCalculateCorrectAmounts() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    // Mock oracle rate
    vm.mockCall(
      address(oracleAdapter),
      abi.encodeWithSelector(IOracleAdapter.getRateIfValid.selector, referenceRateFeedID),
      abi.encode(1e18, 2e18)
    );

    uint256 amountIn = 10e18;
    uint256 amountOutExpected = (5e18 * 997) / 1000; // .3% fee

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = _createRoute(address(tokenB), address(tokenA));

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    assertEq(amounts[1], amountOutExpected);
  }

  function test_getReserves_whenLiquidityAdded_shouldReturnCorrectReserves() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    _addInitialLiquidity(token0, token1, fpmm);

    // Check initial reserves
    (uint256 reserve0, uint256 reserve1) = router.getReserves(token0, token1, address(factory));
    assertEq(reserve0, 1000e18);
    assertEq(reserve1, 1000e18);

    // Add more liquidity
    vm.startPrank(alice);
    IERC20(token0).transfer(fpmm, 1000e18);
    IERC20(token1).transfer(fpmm, 500e18);
    IFPMM(fpmm).mint(alice);
    vm.stopPrank();

    // Check updated reserves
    (reserve0, reserve1) = router.getReserves(token0, token1, address(factory));
    assertEq(reserve0, 2000e18);
    assertEq(reserve1, 1500e18);
  }

  // ============ LIQUIDITY QUOTE TESTS ============

  function test_quoteAddLiquidity_whenNewPool_shouldReturnDesiredAmounts() public {
    _deployFPMM(address(tokenA), address(tokenB));

    uint256 amountADesired = 400e18;
    uint256 amountBDesired = 100e18;

    (uint256 amountA, uint256 amountB, uint256 liquidity) = router.quoteAddLiquidity(
      address(tokenA),
      address(tokenB),
      address(factory),
      amountADesired,
      amountBDesired
    );

    assertEq(amountA, amountADesired);
    assertEq(amountB, amountBDesired);
    assertEq(liquidity, 200e18 - 1e3);
  }

  function test_quoteAddLiquidity_whenExistingPool_shouldReturnDesiredAmounts() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 amount0Desired = 100e18;
    uint256 amount1Desired = 100e18;

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.quoteAddLiquidity(
      token0,
      token1,
      address(factory),
      amount0Desired,
      amount1Desired
    );

    assertEq(amount0, amount0Desired);
    assertEq(amount1, amount1Desired);
    assertEq(liquidity, 100e18); // 10% of total supply since we're adding 10% of initial liquidity
  }

  function test_quoteAddLiquidity_whenImbalancedDesiredAmounts_shouldAdjustToMaintainRatio() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 amount0Desired = 200e18;
    uint256 amount1Desired = 50e18;

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.quoteAddLiquidity(
      token0,
      token1,
      address(factory),
      amount0Desired,
      amount1Desired
    );

    assertEq(amount0, 50e18); // Should be adjusted down to maintain ratio
    assertEq(amount1, 50e18);
    assertEq(liquidity, 50e18); // 5% of total supply since we're adding 5% of initial liquidity
  }

  function test_quoteRemoveLiquidity_whenNonexistentPool_shouldReturnZero() public view {
    (uint256 amountA, uint256 amountB) = router.quoteRemoveLiquidity(
      address(tokenA),
      address(tokenB),
      address(factory),
      100e18
    );

    assertEq(amountA, 0);
    assertEq(amountB, 0);
  }

  function test_quoteRemoveLiquidity_whenPartialLiquidityRemoval_shouldReturnProportionalAmounts() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 liquidityToRemove = 50e18; // Remove 5% of total supply

    (uint256 amount0, uint256 amount1) = router.quoteRemoveLiquidity(
      token0,
      token1,
      address(factory),
      liquidityToRemove
    );

    assertEq(amount0, 50e18); // Should get back 5% of reserves
    assertEq(amount1, 50e18); // Should get back 5% of reserves
  }

  // ============ ADD LIQUIDITY TESTS ============

  function test_addLiquidity_whenNewPool_shouldAddInitialLiquidity() public {
    _deployFPMM(address(tokenA), address(tokenB));
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));

    uint256 amount0Desired = 100e18;
    uint256 amount1Desired = 100e18;

    vm.startPrank(alice);

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      amount0Desired,
      amount1Desired,
      0, // amountAMin
      0, // amountBMin
      alice,
      block.timestamp
    );

    assertEq(amount0, amount0Desired);
    assertEq(amount1, amount1Desired);
    assertEq(liquidity, 100e18 - 1e3);

    address pool = factory.getPool(token0, token1);
    assertEq(IERC20(pool).balanceOf(alice), liquidity);

    vm.stopPrank();
  }

  function test_addLiquidity_whenExistingPool_shouldAddToPool() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 amount0Desired = 50e18;
    uint256 amount1Desired = 50e18;

    vm.startPrank(bob);

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      amount0Desired,
      amount1Desired,
      0, // amountAMin
      0, // amountBMin
      bob,
      block.timestamp
    );

    assertEq(amount0, amount0Desired);
    assertEq(amount1, amount1Desired);
    assertEq(liquidity, 50e18);
    assertEq(IERC20(fpmm).balanceOf(bob), liquidity);

    vm.stopPrank();
  }

  function test_addLiquidity_whenMinimumAmountsNotMet_shouldRevert() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    vm.startPrank(bob);

    // Test insufficient amountA desired
    vm.expectRevert(IRouter.InsufficientAmountADesired.selector);
    router.addLiquidity(
      token0,
      token1,
      50e18, // amount0Desired
      50e18, // amount1Desired
      51e18, // amountAMin - higher than desired
      0, // amountBMin
      bob,
      block.timestamp
    );

    // Test insufficient amountB desired
    vm.expectRevert(IRouter.InsufficientAmountBDesired.selector);
    router.addLiquidity(
      token0,
      token1,
      50e18, // amount0Desired
      50e18, // amount1Desired
      0, // amountAMin
      51e18, // amountBMin - higher than desired
      bob,
      block.timestamp
    );

    // Add liquidity to imbalance pool
    vm.startPrank(alice);
    IERC20(token0).transfer(fpmm, 100e18);
    IERC20(token1).transfer(fpmm, 50e18);
    IFPMM(fpmm).mint(alice);
    vm.stopPrank();

    // Test insufficient amountB (pool is imbalanced)
    vm.expectRevert(IRouter.InsufficientAmountB.selector);
    router.addLiquidity(
      token0,
      token1,
      50e18, // amount0Desired
      50e18, // amount1Desired
      50e18, // amountAMin
      50e18, // amountBMin
      bob,
      block.timestamp
    );

    vm.stopPrank();
  }

  // ============ REMOVE LIQUIDITY TESTS ============

  function test_removeLiquidity_whenValidLiquidity_shouldRemoveCorrectly() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    vm.startPrank(alice);

    uint256 balance0Before = IERC20(token0).balanceOf(alice);
    uint256 balance1Before = IERC20(token1).balanceOf(alice);

    // Add liquidity
    (uint256 amount0Added, uint256 amount1Added, uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      100e18, // amount0Desired
      100e18, // amount1Desired
      100e18, // amountAMin
      100e18, // amountBMin
      alice,
      block.timestamp
    );

    // Approve router to spend LP tokens
    IERC20(fpmm).approve(address(router), liquidity);

    // Remove half of liquidity
    uint256 halfLiquidity = liquidity / 2;
    (uint256 amount0, uint256 amount1) = router.removeLiquidity(
      token0,
      token1,
      halfLiquidity,
      0, // amountAMin
      0, // amountBMin
      alice,
      block.timestamp
    );

    // Verify received amounts are proportional
    assertEq(amount0, amount0Added / 2);
    assertEq(amount1, amount1Added / 2);
    assertEq(IERC20(fpmm).balanceOf(alice), halfLiquidity);

    // Remove remaining liquidity
    router.removeLiquidity(
      token0,
      token1,
      halfLiquidity,
      0, // amountAMin
      0, // amountBMin
      alice,
      block.timestamp
    );
    vm.stopPrank();

    // Verify final balances
    assertEq(IERC20(token0).balanceOf(alice), balance0Before);
    assertEq(IERC20(token1).balanceOf(alice), balance1Before);
    assertEq(IERC20(fpmm).balanceOf(alice), 0);
  }

  function test_removeLiquidity_whenInsufficientAmountA_shouldRevert() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    // Add initial liquidity
    vm.startPrank(alice);

    (, , uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      100e18,
      100e18,
      100e18,
      100e18,
      alice,
      block.timestamp
    );

    IERC20(fpmm).approve(address(router), liquidity);

    // Try to remove liquidity with high minimum amount requirement
    vm.expectRevert(IRouter.InsufficientAmountA.selector);
    router.removeLiquidity(
      token0,
      token1,
      liquidity,
      101e18, // amountAMin > possible amount
      0,
      alice,
      block.timestamp
    );
    vm.stopPrank();
  }

  function test_removeLiquidity_whenInsufficientAmountB_shouldRevert() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    // Add initial liquidity
    vm.startPrank(alice);

    (, , uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      100e18,
      100e18,
      100e18,
      100e18,
      alice,
      block.timestamp
    );

    IERC20(fpmm).approve(address(router), liquidity);

    // Try to remove liquidity with high minimum amount requirement
    vm.expectRevert(IRouter.InsufficientAmountB.selector);
    router.removeLiquidity(
      token0,
      token1,
      liquidity,
      0,
      101e18, // amountBMin > possible amount
      alice,
      block.timestamp
    );
    vm.stopPrank();
  }

  // ============ SWAP TESTS ============

  function test_swapExactTokensForTokens_whenPriceIs1_shouldSwapTokens() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    uint256 amountIn = 10e18;
    uint256 expectedAmountOut = (amountIn * 997) / 1000;

    IRouter.Route memory route = _createRoute(address(tokenA), address(tokenB));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    vm.startPrank(alice);

    uint256 balanceBefore = tokenB.balanceOf(alice);

    router.swapExactTokensForTokens(
      amountIn,
      0, // amountOutMin
      routes,
      alice,
      block.timestamp
    );

    uint256 balanceAfter = tokenB.balanceOf(alice);
    assertEq(balanceAfter - balanceBefore, expectedAmountOut);
    assertEq(tokenA.balanceOf(alice), 1000e18 - amountIn);

    vm.stopPrank();
  }

  function test_swapExactTokensForTokens_whenPriceIsNot1_shouldSwapTokens() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    // Mock oracle rate for 10% higher price
    vm.mockCall(
      address(oracleAdapter),
      abi.encodeWithSelector(IOracleAdapter.getRateIfValid.selector, referenceRateFeedID),
      abi.encode(1e18, 1.1e18)
    );

    IRouter.Route memory route = _createRoute(address(tokenB), address(tokenA));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    uint256 amountIn = 10e18;
    uint256 expectedAmountOut = (((amountIn * 997) / 1000) * 10) / 11;

    vm.startPrank(alice);

    uint256 balanceBefore = tokenA.balanceOf(alice);

    router.swapExactTokensForTokens(amountIn, 0, routes, alice, block.timestamp);

    uint256 balanceAfter = tokenA.balanceOf(alice);
    assertEq(balanceAfter - balanceBefore, expectedAmountOut);
    assertEq(tokenB.balanceOf(alice), 1000e18 - amountIn);

    vm.stopPrank();
  }

  function test_swapExactTokensForTokens_whenInsufficientOutput_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    uint256 amountIn = 10e18;

    IRouter.Route memory route = _createRoute(address(tokenA), address(tokenB));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    vm.startPrank(alice);

    vm.expectRevert(IRouter.InsufficientOutputAmount.selector);
    router.swapExactTokensForTokens(
      amountIn,
      amountIn, // amountOutMin can not be equal to amountIn because of the fee
      routes,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_swapExactTokensForTokensSupportingFeeOnTransferTokens_whenValidSwap_shouldSwapTokens() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    uint256 amountIn = 10e18;
    uint256 expectedAmountOut = (amountIn * 997) / 1000;

    IRouter.Route memory route = _createRoute(address(tokenA), address(tokenB));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    vm.startPrank(alice);

    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn, 0, routes, alice, block.timestamp);

    vm.stopPrank();

    assertEq(tokenA.balanceOf(alice), 1000e18 - amountIn);
    assertEq(tokenB.balanceOf(alice), 1000e18 + expectedAmountOut);
  }

  // ============ ZAP TESTS ============

  function test_zapIn_whenValidTokens_shouldZapInTokens() public {
    // Sort tokens by address
    address[] memory tokens = _sortTokensByAddress();

    // Deploy pools
    address fpmm_0_1 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm_1_2 = _deployFPMM(tokens[1], tokens[2]);
    address fpmm_0_2 = _deployFPMM(tokens[0], tokens[2]);

    // Add initial liquidity to all pools
    _addInitialLiquidity(tokens[0], tokens[1], fpmm_0_1);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm_1_2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm_0_2);

    vm.startPrank(alice);
    _approveRouterMax(tokens);

    // Setup zap parameters
    IRouter.Zap memory zapInPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(factory) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(factory) });

    // Record balances before zap
    uint256 balanceBefore0 = IERC20(tokens[0]).balanceOf(alice);
    uint256 balanceBefore1 = IERC20(tokens[1]).balanceOf(alice);
    uint256 balanceBefore2 = IERC20(tokens[2]).balanceOf(alice);
    uint256 balanceBefore01 = IERC20(fpmm_0_1).balanceOf(alice);
    uint256 balanceBefore12 = IERC20(fpmm_1_2).balanceOf(alice);
    uint256 balanceBefore02 = IERC20(fpmm_0_2).balanceOf(alice);

    // Execute zap
    router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    // Verify token balances
    assertEq(IERC20(tokens[0]).balanceOf(alice), balanceBefore0 - 20e18);
    assertEq(IERC20(tokens[1]).balanceOf(alice), balanceBefore1);
    assertEq(IERC20(tokens[2]).balanceOf(alice), balanceBefore2);

    // Verify LP token balances
    assertEq(IERC20(fpmm_0_1).balanceOf(alice), balanceBefore01);
    assertEq(IERC20(fpmm_0_2).balanceOf(alice), balanceBefore02);
    assertEq(IERC20(fpmm_1_2).balanceOf(alice), balanceBefore12 + (10e18 * 997) / 1000);

    vm.stopPrank();
  }

  function test_zapOut_whenValidLiquidity_shouldZapOutTokens() public {
    // Sort tokens by address
    address[] memory tokens = _sortTokensByAddress();

    // Deploy pools
    address fpmm_0_1 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm_1_2 = _deployFPMM(tokens[1], tokens[2]);
    address fpmm_0_2 = _deployFPMM(tokens[0], tokens[2]);

    // Add initial liquidity to all pools
    _addInitialLiquidity(tokens[0], tokens[1], fpmm_0_1);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm_1_2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm_0_2);

    vm.startPrank(alice);
    _approveRouterMax(tokens);
    IERC20(fpmm_1_2).approve(address(router), type(uint256).max);

    // Setup zap parameters
    IRouter.Zap memory zapOutPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(factory) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(factory) });

    // First add some liquidity to get LP tokens
    router.zapIn(tokens[0], 10e18, 10e18, zapOutPool, routesA, routesB, alice);

    // Record balances before zap out
    uint256 balanceBefore0 = IERC20(tokens[0]).balanceOf(alice);
    uint256 balanceBefore1 = IERC20(tokens[1]).balanceOf(alice);
    uint256 balanceBefore2 = IERC20(tokens[2]).balanceOf(alice);
    uint256 balanceBefore01 = IERC20(fpmm_0_1).balanceOf(alice);
    uint256 balanceBefore12 = IERC20(fpmm_1_2).balanceOf(alice);
    uint256 balanceBefore02 = IERC20(fpmm_0_2).balanceOf(alice);

    // Setup reverse routes for zap out
    routesA[0] = IRouter.Route({ from: tokens[1], to: tokens[0], factory: address(factory) });
    routesB[0] = IRouter.Route({ from: tokens[2], to: tokens[0], factory: address(factory) });

    // Zap out the LP tokens back to token0
    router.zapOut(tokens[0], balanceBefore12, zapOutPool, routesA, routesB);

    // Verify LP tokens are burned
    assertEq(IERC20(fpmm_1_2).balanceOf(alice), 0);

    // Verify other LP token balances unchanged
    assertEq(IERC20(fpmm_0_1).balanceOf(alice), balanceBefore01);
    assertEq(IERC20(fpmm_0_2).balanceOf(alice), balanceBefore02);

    // Verify received token0 back, other token balances unchanged
    assertGt(IERC20(tokens[0]).balanceOf(alice), balanceBefore0);
    assertEq(IERC20(tokens[1]).balanceOf(alice), balanceBefore1);
    assertEq(IERC20(tokens[2]).balanceOf(alice), balanceBefore2);

    vm.stopPrank();
  }

  // ============ INTERNAL FUNCTIONS ============

  function _createRoute(address from, address to) internal pure returns (IRouter.Route memory) {
    return
      IRouter.Route({
        from: from,
        to: to,
        factory: address(0) // Use default factory
      });
  }

  function _sortTokensByAddress() internal view returns (address[] memory tokens) {
    tokens = new address[](3);
    tokens[0] = address(tokenA);
    tokens[1] = address(tokenB);
    tokens[2] = address(tokenC);

    // Sort tokens by address
    for (uint256 i = 0; i < tokens.length; i++) {
      for (uint256 j = i + 1; j < tokens.length; j++) {
        if (tokens[i] > tokens[j]) {
          address tempToken = tokens[i];
          tokens[i] = tokens[j];
          tokens[j] = tempToken;
        }
      }
    }
  }

  function _approveRouterMax(address[] memory tokens) internal {
    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20(tokens[i]).approve(address(router), type(uint256).max);
    }
  }
}
