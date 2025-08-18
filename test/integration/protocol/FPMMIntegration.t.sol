// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { Test } from "forge-std/Test.sol";

import { TestERC20 } from "test/utils/mocks/TestERC20.sol";

import { Router } from "contracts/swap/router/Router.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { IPool } from "contracts/swap/router/interfaces/IPool.sol";
import { IPoolFactory } from "contracts/swap/router/interfaces/IPoolFactory.sol";
import { IFactoryRegistry } from "contracts/swap/router/interfaces/IFactoryRegistry.sol";
import { IWETH } from "contracts/swap/router/interfaces/IWETH.sol";
import { IVoter } from "contracts/swap/router/interfaces/IVoter.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { console } from "forge-std/console.sol";

contract RouterFPMMIntegrationTest is Test {
  // Router contracts
  Router public router;
  FPMMFactory public factory;

  // FPMM contracts
  FPMM public fpmmImplementation;

  // Test tokens
  TestERC20 public tokenA;
  TestERC20 public tokenB;
  TestERC20 public tokenC;

  // Test addresses
  address public deployer = makeAddr("deployer");
  address public alice = makeAddr("alice");
  address public bob = makeAddr("bob");
  address public charlie = makeAddr("charlie");
  address public owner = makeAddr("owner");

  address public createX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

  address public referenceRateFeedID = makeAddr("referenceRateFeedID");

  address public factoryRegistry = makeAddr("factoryRegistry");
  address public voter = makeAddr("voter");
  address public weth = makeAddr("weth");
  address public sortedOracles = makeAddr("sortedOracles");
  address public breakerBox = makeAddr("breakerBox");
  address public proxyAdmin = makeAddr("proxyAdmin");
  address public governance = makeAddr("governance");

  uint256 public celoFork = vm.createFork("https://forno.celo.org");

  function setUp() public virtual {
    vm.warp(60 * 60 * 24 * 10); // Start at a non-zero timestamp

    vm.selectFork(celoFork);

    // Deploy test tokens
    tokenA = new TestERC20("TokenA", "TKA");
    tokenB = new TestERC20("TokenB", "TKB");
    tokenC = new TestERC20("TokenC", "TKC");

    factory = new FPMMFactory(false);
    fpmmImplementation = new FPMM(true);

    router = new Router(
      address(0), // forwarder
      factoryRegistry,
      address(factory),
      voter,
      weth
    );

    factory.initialize(sortedOracles, proxyAdmin, breakerBox, governance, address(fpmmImplementation));

    // Setup mock behavior
    _setupMocks();

    // Fund test accounts
    _fundTestAccounts();
  }

  // Test setup verification
  function test_setup_shouldDeployContractsCorrectly() public {
    assertEq(factory.sortedOracles(), sortedOracles);
    assertEq(factory.proxyAdmin(), proxyAdmin);
    assertEq(factory.breakerBox(), breakerBox);
    assertEq(factory.isRegisteredImplementation(address(fpmmImplementation)), true);
    address[] memory registeredImplementations = factory.registeredImplementations();
    assertEq(registeredImplementations.length, 1);
    assertEq(registeredImplementations[0], address(fpmmImplementation));
    assertEq(factory.governance(), governance);
    assertEq(factory.owner(), governance);
  }

  function test_deploy_shouldDeployFPMMCorrectly() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));

    if (address(tokenA) < address(tokenB)) {
      assertEq(IFPMM(fpmm).token0(), address(tokenA));
      assertEq(IFPMM(fpmm).token1(), address(tokenB));
      assertEq(IERC20(fpmm).symbol(), "FPMM-TKA/TKB");
    } else {
      assertEq(IFPMM(fpmm).token0(), address(tokenB));
      assertEq(IFPMM(fpmm).token1(), address(tokenA));
      assertEq(IERC20(fpmm).symbol(), "FPMM-TKB/TKA");
    }

    assertEq(IERC20(fpmm).decimals(), 18);
    assertEq(address(IFPMM(fpmm).sortedOracles()), sortedOracles);
    assertEq(IFPMM(fpmm).referenceRateFeedID(), referenceRateFeedID);
    assertEq(address(IFPMM(fpmm).breakerBox()), breakerBox);
    assertEq(OwnableUpgradeable(fpmm).owner(), governance);

    assertEq(IFPMM(fpmm).decimals0(), 1e18);
    assertEq(IFPMM(fpmm).decimals1(), 1e18);
  }

  // Test pool creation and management
  function test_poolFor_shouldReturnCorrectPoolAddress() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    address pool = router.poolFor(address(tokenA), address(tokenB), false, address(0));
    assertEq(pool, fpmm);

    // Should work with reversed token order
    address poolReversed = router.poolFor(address(tokenB), address(tokenA), false, address(0));
    assertEq(poolReversed, fpmm);
  }

  function test_sortTokens_shouldSortTokensCorrectly() public {
    address _token0 = address(0x0000000000000000000000000000000000000011);
    address _token1 = address(0x0000000000000000000000000000000000000022);
    (address token0, address token1) = router.sortTokens(_token0, _token1);

    assertEq(token0, _token0);
    assertEq(token1, _token1);

    (token0, token1) = router.sortTokens(address(_token1), address(_token0));

    assertEq(token0, _token0);
    assertEq(token1, _token1);
  }

  function test_sortTokens_shouldRevertForSameTokens() public {
    vm.expectRevert(IRouter.SameAddresses.selector);
    router.sortTokens(address(tokenA), address(tokenA));
  }

  function test_sortTokens_shouldRevertForZeroAddress() public {
    vm.expectRevert(IRouter.ZeroAddress.selector);
    router.sortTokens(address(0), address(tokenA));
  }

  // Test getAmountsOut
  function test_getAmountsOut_shouldCalculateCorrectAmounts_whenTokenAIsToken0AndOracleRateIs1() public {
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

  function test_getAmountsOut_shouldCalculateCorrectAmounts_whenTokenBIsToken0AndOracleRateIs2() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
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

  function test_getReserves_shouldReturnCorrectReserves() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    _addInitialLiquidity(token0, token1, fpmm);
    (uint256 reserve0, uint256 reserve1, ) = IFPMM(fpmm).getReserves();
    assertEq(reserve0, 1000e18);
    assertEq(reserve1, 1000e18);

    vm.startPrank(alice);
    IERC20(token0).transfer(fpmm, 1000e18);
    IERC20(token1).transfer(fpmm, 500e18);
    IFPMM(fpmm).mint(alice);
    vm.stopPrank();

    (reserve0, reserve1, ) = IFPMM(fpmm).getReserves();
    assertEq(reserve0, 2000e18);
    assertEq(reserve1, 1500e18);
  }
  function test_quoteAddLiquidity_shouldReturnCorrectAmountsForNewPool() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));

    uint256 amountADesired = 400e18;
    uint256 amountBDesired = 100e18;

    (uint256 amountA, uint256 amountB, uint256 liquidity) = router.quoteAddLiquidity(
      address(tokenA),
      address(tokenB),
      false,
      address(factory),
      amountADesired,
      amountBDesired
    );

    assertEq(amountA, amountADesired);
    assertEq(amountB, amountBDesired);
    assertEq(liquidity, 200e18 - 1000);
  }

  function test_quoteAddLiquidity_shouldReturnCorrectAmountsForExistingPool() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 amount0Desired = 100e18;
    uint256 amount1Desired = 100e18;

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.quoteAddLiquidity(
      token0,
      token1,
      false,
      address(factory),
      amount0Desired,
      amount1Desired
    );

    assertEq(amount0, amount0Desired);
    assertEq(amount1, amount1Desired);
    assertEq(liquidity, 100e18); // 10% of total supply since we're adding 10% of initial liquidity
  }

  function test_quoteAddLiquidity_shouldHandleImbalancedDesiredAmounts() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 amount0Desired = 200e18;
    uint256 amount1Desired = 50e18;

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.quoteAddLiquidity(
      token0,
      token1,
      false,
      address(factory),
      amount0Desired,
      amount1Desired
    );

    assertEq(amount0, 50e18); // Should be adjusted down to maintain ratio
    assertEq(amount1, 50e18);
    assertEq(liquidity, 50e18); // 5% of total supply since we're adding 5% of initial liquidity
  }

  function test_quoteRemoveLiquidity_shouldReturnZeroForNonexistentPool() public {
    (uint256 amountA, uint256 amountB) = router.quoteRemoveLiquidity(
      address(tokenA),
      address(tokenB),
      false,
      address(factory),
      100e18
    );

    assertEq(amountA, 0);
    assertEq(amountB, 0);
  }

  function test_quoteRemoveLiquidity_shouldHandlePartialLiquidityRemoval() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 liquidityToRemove = 50e18; // Remove 5% of total supply

    (uint256 amount0, uint256 amount1) = router.quoteRemoveLiquidity(
      token0,
      token1,
      false,
      address(factory),
      liquidityToRemove
    );

    assertEq(amount0, 50e18); // Should get back 5% of reserves
    assertEq(amount1, 50e18); // Should get back 5% of reserves
  }

  function test_addLiquidity_shouldAddInitialLiquidity() public {
    _deployFPMM(address(tokenA), address(tokenB));

    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));

    uint256 amount0Desired = 100e18;
    uint256 amount1Desired = 100e18;

    vm.startPrank(alice);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      false,
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

    address pool = factory.deployedFPMMs(token0, token1);
    assertEq(IERC20(pool).balanceOf(alice), liquidity);

    vm.stopPrank();
  }

  function test_addLiquidity_shouldAddToExistingPool() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    uint256 amount0Desired = 50e18;
    uint256 amount1Desired = 50e18;

    vm.startPrank(bob);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      false,
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

  function test_addLiquidity_shouldRespectMinimumAmounts() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    vm.startPrank(bob);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);

    vm.expectRevert(abi.encodeWithSignature("InsufficientAmountADesired()"));
    router.addLiquidity(
      token0,
      token1,
      false,
      50e18, // amount0Desired
      50e18, // amount1Desired
      51e18, // amountAMin - higher than desired
      0, // amountBMin
      bob,
      block.timestamp
    );

    vm.expectRevert(abi.encodeWithSignature("InsufficientAmountBDesired()"));
    router.addLiquidity(
      token0,
      token1,
      false,
      50e18, // amount0Desired
      50e18, // amount1Desired
      0, // amountAMin
      51e18, // amountBMin - higher than desired
      bob,
      block.timestamp
    );

    // add liquidity to imbalance pool
    vm.startPrank(alice);
    IERC20(token0).transfer(fpmm, 100e18);
    IERC20(token1).transfer(fpmm, 50e18);
    IFPMM(fpmm).mint(alice);
    vm.stopPrank();

    // the pool is imbalanced, so the amountBDesired should be adjusted down to maintain the ratio
    vm.expectRevert(abi.encodeWithSignature("InsufficientAmountB()"));
    router.addLiquidity(
      token0,
      token1,
      false,
      50e18, // amount0Desired
      50e18, // amount1Desired
      50e18, // amountAMin
      50e18, // amountBMin
      bob,
      block.timestamp
    );

    // add liquidity to rebalance the pool
    vm.startPrank(alice);
    IERC20(token0).transfer(fpmm, 50e18);
    IERC20(token1).transfer(fpmm, 100e18);
    IFPMM(fpmm).mint(alice);
    vm.stopPrank();

    // pool is rebalanced
    vm.startPrank(bob);
    router.addLiquidity(
      token0,
      token1,
      false,
      50e18, // amount0Desired
      50e18, // amount1Desired
      50e18, // amountAMin
      50e18, // amountBMin
      bob,
      block.timestamp
    );

    // add liquidity to debalance the pool to the other side
    vm.startPrank(alice);
    IERC20(token0).transfer(fpmm, 50e18);
    IERC20(token1).transfer(fpmm, 100e18);
    IFPMM(fpmm).mint(alice);
    vm.stopPrank();

    vm.expectRevert(abi.encodeWithSignature("InsufficientAmountA()"));
    router.addLiquidity(
      token0,
      token1,
      false,
      50e18, // amount0Desired
      50e18, // amount1Desired
      50e18, // amountAMin
      50e18, // amountBMin
      bob,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_addLiquidity_shouldRevertForInvalidDeadline() public {
    vm.expectRevert(abi.encodeWithSignature("Expired()"));
    router.addLiquidity(
      address(tokenA),
      address(tokenB),
      false,
      50e18, // amount0Desired
      50e18, // amount1Desired
      50e18, // amountAMin
      50e18, // amountBMin
      bob,
      block.timestamp - 1
    );
  }
  function test_removeLiquidity_shouldRemoveLiquidityCorrectly() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    vm.startPrank(alice);
    IERC20(token0).approve(address(router), 100e18);
    IERC20(token1).approve(address(router), 100e18);

    uint256 balance0Before = IERC20(token0).balanceOf(alice);
    uint256 balance1Before = IERC20(token1).balanceOf(alice);

    (uint256 amount0Added, uint256 amount1Added, uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      false,
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
      false,
      halfLiquidity,
      0, // amountAMin
      0, // amountBMin
      alice,
      block.timestamp
    );

    // Verify received amounts are proportional
    assertEq(amount0, amount0Added / 2);
    assertEq(amount1, amount1Added / 2);

    // Verify remaining liquidity
    assertEq(IERC20(fpmm).balanceOf(alice), halfLiquidity);

    // remove the remaining liquidity from alice
    router.removeLiquidity(
      token0,
      token1,
      false,
      halfLiquidity,
      0, // amountAMin
      0, // amountBMin
      alice,
      block.timestamp
    );
    vm.stopPrank();

    assertEq(IERC20(token0).balanceOf(alice), balance0Before);
    assertEq(IERC20(token1).balanceOf(alice), balance1Before);
    assertEq(IERC20(fpmm).balanceOf(alice), 0);
  }

  function test_removeLiquidity_shouldRevertForInsufficientAmountA() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    // Add initial liquidity
    vm.startPrank(alice);
    IERC20(token0).approve(address(router), 100e18);
    IERC20(token1).approve(address(router), 100e18);

    (, , uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      false,
      100e18,
      100e18,
      100e18,
      100e18,
      alice,
      block.timestamp
    );

    IERC20(fpmm).approve(address(router), liquidity);

    // Try to remove liquidity with high minimum amount requirement
    vm.expectRevert(abi.encodeWithSignature("InsufficientAmountA()"));
    router.removeLiquidity(
      token0,
      token1,
      false,
      liquidity,
      101e18, // amountAMin > possible amount
      0,
      alice,
      block.timestamp
    );
    vm.stopPrank();
  }

  function test_removeLiquidity_shouldRevertForInsufficientAmountB() public {
    (address token0, address token1) = router.sortTokens(address(tokenA), address(tokenB));
    address fpmm = _deployFPMM(token0, token1);
    _addInitialLiquidity(token0, token1, fpmm);

    // Add initial liquidity
    vm.startPrank(alice);
    IERC20(token0).approve(address(router), 100e18);
    IERC20(token1).approve(address(router), 100e18);

    (, , uint256 liquidity) = router.addLiquidity(
      token0,
      token1,
      false,
      100e18,
      100e18,
      100e18,
      100e18,
      alice,
      block.timestamp
    );

    IERC20(fpmm).approve(address(router), liquidity);

    // Try to remove liquidity with high minimum amount requirement
    vm.expectRevert(abi.encodeWithSignature("InsufficientAmountB()"));
    router.removeLiquidity(
      token0,
      token1,
      false,
      liquidity,
      0,
      101e18, // amountBMin > possible amount
      alice,
      block.timestamp
    );
    vm.stopPrank();
  }

  function test_swapExactTokensForTokens_shouldSwapTokens_whenPriceIs1() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    uint256 amountIn = 10e18;
    uint256 expectedAmountOut = (amountIn * 997) / 1000;

    IRouter.Route memory route = _createRoute(address(tokenA), address(tokenB));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    vm.startPrank(alice);
    tokenA.approve(address(router), amountIn);

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

  function test_swapExactTokensForTokens_shouldSwapTokens_whenPriceIsNot1() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
      abi.encode(1e18, 1.1e18) // 10% higher price
    );

    IRouter.Route memory route = _createRoute(address(tokenB), address(tokenA));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    uint256 amountIn = 10e18;
    uint256 expectedAmountOut = (((amountIn * 997) / 1000) * 10) / 11;

    vm.startPrank(alice);
    tokenB.approve(address(router), amountIn);

    uint256 balanceBefore = tokenA.balanceOf(alice);

    router.swapExactTokensForTokens(amountIn, 0, routes, alice, block.timestamp);

    uint256 balanceAfter = tokenA.balanceOf(alice);
    assertEq(balanceAfter - balanceBefore, expectedAmountOut);
    assertEq(tokenB.balanceOf(alice), 1000e18 - amountIn);

    vm.stopPrank();
  }

  function test_swapExactTokensForTokens_shouldRevertForInsufficientOutput() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    uint256 amountIn = 10e18;

    IRouter.Route memory route = _createRoute(address(tokenA), address(tokenB));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    vm.startPrank(alice);
    tokenA.approve(address(router), amountIn);

    vm.expectRevert(abi.encodeWithSignature("InsufficientOutputAmount()"));
    router.swapExactTokensForTokens(
      amountIn,
      amountIn, // amountOutMin
      routes,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_unsafeSwapExactTokensForTokens_shouldSwapTokensWithoutSlippageProtection() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    uint256 amountIn = 10e18;

    IRouter.Route memory route = _createRoute(address(tokenA), address(tokenB));
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = route;

    vm.startPrank(alice);
    tokenA.approve(address(router), amountIn);

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);
    router.UNSAFE_swapExactTokensForTokens(amounts, routes, alice, block.timestamp);

    vm.stopPrank();

    assertEq(tokenA.balanceOf(alice), 1000e18 - amountIn);
    assertEq(tokenB.balanceOf(alice), 1000e18 + amounts[1]);
  }

  function test_swapExactTokensForTokens_shouldRevertForExpiredDeadline() public {
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), stable: false, factory: address(factory) });

    vm.expectRevert(abi.encodeWithSignature("Expired()"));
    router.swapExactTokensForTokens(10e18, 0, routes, alice, block.timestamp - 1);
  }

  function test_removeLiquidity_shouldRevertForExpiredDeadline() public {
    vm.expectRevert(abi.encodeWithSignature("Expired()"));
    router.removeLiquidity(address(tokenA), address(tokenB), false, 100e18, 0, 0, alice, block.timestamp - 1);
  }

  function _setupMocks() internal {
    // Mock factory registry to approve our pool factory
    vm.mockCall(
      factoryRegistry,
      abi.encodeWithSelector(IFactoryRegistry.isPoolFactoryApproved.selector, address(factory)),
      abi.encode(true)
    );

    // Mock sorted oracles to return a rate
    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
      abi.encode(1e18, 1e18)
    );

    // Mock breaker box to return a trading mode
    vm.mockCall(
      address(breakerBox),
      abi.encodeWithSelector(IBreakerBox.getRateFeedTradingMode.selector, referenceRateFeedID),
      abi.encode(0) // TRADING_MODE_BIDIRECTIONAL
    );
  }

  function _fundTestAccounts() internal {
    // Fund accounts with tokens
    deal(address(tokenA), alice, 1000e18);
    deal(address(tokenB), alice, 1000e18);
    deal(address(tokenC), alice, 1000e18);

    deal(address(tokenA), bob, 1000e18);
    deal(address(tokenB), bob, 1000e18);
    deal(address(tokenC), bob, 1000e18);

    deal(address(tokenA), charlie, 1000e18);
    deal(address(tokenB), charlie, 1000e18);
    deal(address(tokenC), charlie, 1000e18);

    // Fund with native token
    vm.deal(alice, 1000e18);
    vm.deal(bob, 1000e18);
    vm.deal(charlie, 1000e18);
  }

  function _addInitialLiquidity(address token0, address token1, address fpmm) internal {
    deal(token0, fpmm, 1000e18);
    deal(token1, fpmm, 1000e18);

    // Mint liquidity tokens
    IFPMM(fpmm).mint(makeAddr("LP"));
  }

  function _deployFPMM(address token0, address token1) internal returns (address fpmm) {
    vm.prank(governance);
    fpmm = factory.deployFPMM(address(fpmmImplementation), address(token0), address(token1), referenceRateFeedID);
  }

  // Helper function to create a route
  function _createRoute(address from, address to) internal pure returns (IRouter.Route memory) {
    return
      IRouter.Route({
        from: from,
        to: to,
        stable: false,
        factory: address(0) // Use default factory
      });
  }

  // // Helper function to get current deadline
  // function getDeadline() internal view returns (uint256) {
  //     return block.timestamp + 3600; // 1 hour from now
  // }
}
