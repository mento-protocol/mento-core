// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

// Router contracts
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";

// FPMM contracts
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";

// Interfaces
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IRPoolFactory } from "contracts/swap/router/interfaces/IRPoolFactory.sol";

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
    vm.expectRevert(IRouter.PoolFactoryDoesNotExist.selector);
    router.poolFor(address(tokenA), address(tokenB), makeAddr("unknownFactory"));
  }

  function test_poolFor_whenCustomFactoryProvided_shouldUseCustomFactory() public {
    FPMMFactory customFactory = new FPMMFactory(false);

    customFactory.initialize(
      oracleAdapter,
      address(proxyAdmin),
      governance,
      address(fpmmImplementation),
      defaultFpmmParams
    );

    vm.prank(governance);
    factoryRegistry.approve(address(customFactory));

    vm.expectCall(
      address(customFactory),
      abi.encodeWithSelector(IRPoolFactory.getOrPrecomputeProxyAddress.selector, address(tokenA), address(tokenB))
    );
    address pool = router.poolFor(address(tokenA), address(tokenB), address(customFactory));
    vm.prank(governance);
    address actualPool = address(
      customFactory.deployFPMM(
        address(fpmmImplementation),
        address(tokenA),
        address(tokenB),
        referenceRateFeedID,
        false
      )
    );
    assertEq(pool, actualPool);
  }

  function test_getAmountsOut_whenPoolDoesNotExist_shouldRevert() public {
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.expectRevert(IRouter.PoolDoesNotExist.selector);
    router.getAmountsOut(1000e18, routes);
  }

  function test_getAmountsOut_whenFactoryIsNotApproved_shouldRevert() public {
    FPMMFactory customFactory = new FPMMFactory(false);
    customFactory.initialize(
      oracleAdapter,
      address(proxyAdmin),
      governance,
      address(fpmmImplementation),
      defaultFpmmParams
    );

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(customFactory) });

    vm.expectRevert(IRouter.PoolFactoryDoesNotExist.selector);
    router.getAmountsOut(1000e18, routes);

    vm.prank(governance);
    factoryRegistry.approve(address(customFactory));

    vm.expectRevert(IRouter.PoolDoesNotExist.selector);
    router.getAmountsOut(1000e18, routes);
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

  function test_getReserves_whenFactoryIsNotApproved_shouldRevert() public {
    FPMMFactory customFactory = new FPMMFactory(false);
    customFactory.initialize(
      oracleAdapter,
      address(proxyAdmin),
      governance,
      address(fpmmImplementation),
      defaultFpmmParams
    );

    vm.prank(governance);
    address fpmm = customFactory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenB),
      referenceRateFeedID,
      false
    );
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.expectRevert(IRouter.PoolFactoryDoesNotExist.selector);
    router.getReserves(address(tokenA), address(tokenB), address(customFactory));

    vm.prank(governance);
    factoryRegistry.approve(address(customFactory));

    (uint256 reserveA, uint256 reserveB) = router.getReserves(address(tokenA), address(tokenB), address(customFactory));

    assertEq(reserveA, 1000e18);
    assertEq(reserveB, 1000e18);
  }

  function test_quoteAddLiquidity_whenExistingPool_shouldReturnCorrectAmounts() public {
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
    assertEq(liquidity, 1000e18);
  }

  function test_quoteRemoveLiquidity_whenPoolExists_shouldReturnCorrectAmounts() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

    (uint256 amountA, uint256 amountB) = router.quoteRemoveLiquidity(token0, token1, address(factory), 100e18);

    assertEq(amountA, 100e18);
    assertEq(amountB, 100e18);
  }

  function test_quoteRemoveLiquidity_whenPoolDoesNotExist_shouldReturnZero() public view {
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
