// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { Test } from "forge-std/Test.sol";
import { TestERC20 } from "test/utils/mocks/TestERC20.sol";

// Router contracts
import { Router } from "contracts/swap/router/Router.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";

// FPMM contracts
import { FPMM } from "contracts/swap/FPMM.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IFPMMFactory } from "contracts/interfaces/IFPMMFactory.sol";
// Interfaces
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IFactoryRegistry } from "contracts/swap/router/interfaces/IFactoryRegistry.sol";

// Forge
import { console } from "forge-std/console.sol";

// Base integration
import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";

/**
 * @title RouterAdvancedTests
 * @notice Advanced tests for Router functionality including edge cases and error conditions
 */
contract RouterAdvancedTests is FPMMBaseIntegration {
  // ============ STATE VARIABLES ============

  // ============ SETUP ============

  function setUp() public override {
    super.setUp();
  }

  // ============ ERROR CONDITION TESTS ============

  function test_poolFor_whenFactoryNotApproved_shouldRevert() public {
    // Mock factory registry to not approve our pool factory
    vm.mockCall(
      factoryRegistry,
      abi.encodeWithSelector(IFactoryRegistry.isPoolFactoryApproved.selector, address(factory)),
      abi.encode(false)
    );

    vm.expectRevert(IRouter.PoolFactoryDoesNotExist.selector);
    router.poolFor(address(tokenA), address(tokenB), address(factory));
  }

  function test_poolFor_whenCustomFactoryProvided_shouldUseCustomFactory() public {
    FPMMFactory customFactory = new FPMMFactory(false);

    customFactory.initialize(sortedOracles, proxyAdmin, breakerBox, governance, address(fpmmImplementation));

    // Mock factory registry to approve custom factory
    vm.mockCall(
      factoryRegistry,
      abi.encodeWithSelector(IFactoryRegistry.isPoolFactoryApproved.selector, address(customFactory)),
      abi.encode(true)
    );
    (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

    vm.expectCall(
      address(customFactory),
      abi.encodeWithSelector(IFPMMFactory.getOrPrecomputeProxyAddress.selector, address(token0), address(token1))
    );
    address pool = router.poolFor(address(tokenA), address(tokenB), address(customFactory));
    assertTrue(pool != address(0));
  }

  function test_getAmountsOut_whenPoolDoesNotExist_shouldReturnZero() public {
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(1000e18, routes);
    assertEq(amounts.length, 2);
    assertEq(amounts[0], 1000e18);
    assertEq(amounts[1], 0);
  }

  function test_addLiquidity_whenPoolDoesNotExist_shouldRevert() public {
    vm.startPrank(alice);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    vm.expectRevert(IRouter.PoolDoesNotExist.selector);
    router.addLiquidity(address(tokenA), address(tokenB), 1000e18, 1000e18, 0, 0, alice, block.timestamp);

    vm.stopPrank();
  }

  function test_removeLiquidity_whenPoolDoesNotExist_shouldRevert() public {
    vm.startPrank(alice);

    vm.expectRevert("Address: call to non-contract");
    router.removeLiquidity(address(tokenA), address(tokenB), 1000e18, 0, 0, alice, block.timestamp);

    vm.stopPrank();
  }

  function test_swapExactTokensForTokens_whenPoolDoesNotExist_shouldRevert() public {
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.startPrank(alice);
    tokenA.approve(address(router), 1000e18);

    vm.expectRevert();
    router.swapExactTokensForTokens(1000e18, 0, routes, alice, block.timestamp);

    vm.stopPrank();
  }

  // ============ DEADLINE TESTS ============

  function test_addLiquidity_whenExpiredDeadline_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.startPrank(alice);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    vm.expectRevert(IRouter.Expired.selector);
    router.addLiquidity(address(tokenA), address(tokenB), 1000e18, 1000e18, 0, 0, alice, block.timestamp - 1);

    vm.stopPrank();
  }

  function test_removeLiquidity_whenExpiredDeadline_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.startPrank(alice);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    vm.expectRevert(IRouter.Expired.selector);
    router.removeLiquidity(address(tokenA), address(tokenB), 1000e18, 0, 0, alice, block.timestamp - 1);

    vm.stopPrank();
  }

  function test_swapExactTokensForTokens_whenExpiredDeadline_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.startPrank(alice);
    tokenA.approve(address(router), 1000e18);

    vm.expectRevert(IRouter.Expired.selector);
    router.swapExactTokensForTokens(1000e18, 0, routes, alice, block.timestamp - 1);

    vm.stopPrank();
  }

  // ============ INSUFFICIENT AMOUNT TESTS ============

  function test_addLiquidity_whenInsufficientAmountADesired_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.startPrank(alice);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    vm.expectRevert(IRouter.InsufficientAmountADesired.selector);
    router.addLiquidity(
      address(tokenA),
      address(tokenB),
      1000e18,
      1000e18,
      1001e18, // amountAMin > amountADesired
      0,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_addLiquidity_whenInsufficientAmountBDesired_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.startPrank(alice);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    vm.expectRevert(IRouter.InsufficientAmountBDesired.selector);
    router.addLiquidity(
      address(tokenA),
      address(tokenB),
      1000e18,
      1000e18,
      0,
      1001e18, // amountBMin > amountBDesired
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_removeLiquidity_whenInsufficientAmountA_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

    // Add some liquidity first
    vm.startPrank(alice);

    (, , uint256 liquidity) = router.addLiquidity(token0, token1, 1000e18, 1000e18, 0, 0, alice, block.timestamp);

    // Approve router to spend LP tokens
    IERC20(fpmm).approve(address(router), liquidity);

    vm.expectRevert(IRouter.InsufficientAmountA.selector);
    router.removeLiquidity(
      token0,
      token1,
      liquidity,
      1001e18, // amountAMin > possible amount
      0,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_removeLiquidity_whenInsufficientAmountB_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

    // Add some liquidity first
    vm.startPrank(alice);

    (, , uint256 liquidity) = router.addLiquidity(token0, token1, 1000e18, 1000e18, 0, 0, alice, block.timestamp);

    // Approve router to spend LP tokens
    IERC20(fpmm).approve(address(router), liquidity);

    vm.expectRevert(IRouter.InsufficientAmountB.selector);
    router.removeLiquidity(
      token0,
      token1,
      liquidity,
      0,
      1001e18, // amountBMin > possible amount
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_swapExactTokensForTokens_whenInsufficientOutput_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.startPrank(alice);
    tokenA.approve(address(router), 1000e18);

    vm.expectRevert(IRouter.InsufficientOutputAmount.selector);
    router.swapExactTokensForTokens(
      1000e18,
      1000e18, // amountOutMin >= amountIn (impossible due to fees)
      routes,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  // ============ COMPLEX ROUTING TESTS ============

  function test_getAmountsOut_whenMultipleRoutes_shouldCalculateCorrectly() public {
    // Deploy multiple pools
    address fpmm1 = _deployFPMM(address(tokenA), address(tokenB));
    address fpmm2 = _deployFPMM(address(tokenB), address(tokenC));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm1);
    _addInitialLiquidity(address(tokenB), address(tokenC), fpmm2);

    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });
    routes[1] = IRouter.Route({ from: address(tokenB), to: address(tokenC), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(1000e18, routes);

    assertEq(amounts.length, 3);
    assertEq(amounts[0], 1000e18);
    uint256 expectedAmountB = (1000e18 * 997) / 1000;
    assertEq(amounts[1], expectedAmountB);
    uint256 expectedAmountC = (expectedAmountB * 997) / 1000;
    assertEq(amounts[2], expectedAmountC);
  }

  function test_swapExactTokensForTokens_whenMultipleRoutes_shouldSwapCorrectly() public {
    // Deploy multiple pools
    address fpmm1 = _deployFPMM(address(tokenA), address(tokenB));
    address fpmm2 = _deployFPMM(address(tokenB), address(tokenC));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm1);
    _addInitialLiquidity(address(tokenB), address(tokenC), fpmm2);

    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });
    routes[1] = IRouter.Route({ from: address(tokenB), to: address(tokenC), factory: address(0) });

    vm.startPrank(alice);
    tokenA.approve(address(router), 1000e18);

    uint256 balanceBefore = tokenC.balanceOf(alice);

    uint256[] memory amounts = router.swapExactTokensForTokens(1000e18, 0, routes, alice, block.timestamp);

    assertEq(amounts.length, 3);
    assertEq(amounts[0], 1000e18);
    uint256 expectedAmountB = (1000e18 * 997) / 1000;
    assertEq(amounts[1], expectedAmountB);
    uint256 expectedAmountC = (expectedAmountB * 997) / 1000;
    assertEq(amounts[2], expectedAmountC);
    assertEq(tokenC.balanceOf(alice), balanceBefore + expectedAmountC);

    vm.stopPrank();
  }

  // ============ FEE-ON-TRANSFER TOKEN TESTS ============

  function test_swapExactTokensForTokensSupportingFeeOnTransferTokens_whenValidSwap_shouldSwapCorrectly() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.startPrank(alice);
    tokenA.approve(address(router), 1000e18);

    uint256 balanceBefore = tokenB.balanceOf(alice);

    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(1000e18, 0, routes, alice, block.timestamp);

    uint256 expectedAmountB = (1000e18 * 997) / 1000;
    assertEq(tokenB.balanceOf(alice), balanceBefore + expectedAmountB);

    vm.stopPrank();
  }

  function test_swapExactTokensForTokensSupportingFeeOnTransferTokens_whenInsufficientOutput_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.startPrank(alice);
    tokenA.approve(address(router), 1000e18);

    vm.expectRevert(IRouter.InsufficientOutputAmount.selector);
    router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      1000e18,
      1000e18, // amountOutMin >= amountIn (impossible due to fees)
      routes,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  // ============ OTHER TESTS ============

  function test_getReserves_whenPoolExists_shouldReturnCorrectReserves() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    (uint256 reserveA, uint256 reserveB) = router.getReserves(address(tokenA), address(tokenB), address(0));

    assertEq(reserveA, 1000e18);
    assertEq(reserveB, 1000e18);
  }

  function test_getReserves_whenPoolDoesNotExist_shouldRevert() public {
    vm.expectRevert();
    router.getReserves(address(tokenA), address(tokenB), address(0));
  }

  function test_quoteAddLiquidity_whenNewPool_shouldReturnDesiredAmounts() public {
    (uint256 amountA, uint256 amountB, uint256 liquidity) = router.quoteAddLiquidity(
      address(tokenA),
      address(tokenB),
      address(factory),
      1000e18,
      1000e18
    );

    assertEq(amountA, 1000e18);
    assertEq(amountB, 1000e18);
    assertEq(liquidity, 1000e18 - 1e3);
  }

  function test_quoteAddLiquidity_whenExistingPool_shouldReturnAdjustedAmounts() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    (uint256 amountA, uint256 amountB, uint256 liquidity) = router.quoteAddLiquidity(
      address(tokenA),
      address(tokenB),
      address(factory),
      1000e18,
      1000e18
    );

    assertEq(amountA, 1000e18);
    assertEq(amountB, 1000e18);
    assertEq(liquidity, 1000e18 - 1e3);
  }

  function test_quoteRemoveLiquidity_whenPoolExists_shouldReturnCorrectAmounts() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

    (uint256 amountA, uint256 amountB) = router.quoteRemoveLiquidity(token0, token1, address(factory), 100e18);

    assertEq(amountA, 100e18);
    assertEq(amountB, 100e18);
  }

  function test_quoteRemoveLiquidity_whenPoolDoesNotExist_shouldReturnZero() public {
    (uint256 amountA, uint256 amountB) = router.quoteRemoveLiquidity(
      address(tokenA),
      address(tokenB),
      address(factory),
      100e18
    );

    assertEq(amountA, 0);
    assertEq(amountB, 0);
  }
}
