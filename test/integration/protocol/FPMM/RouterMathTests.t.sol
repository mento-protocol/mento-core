// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

// Interfaces
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";

// Base integration
import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";

/**
 * @title RouterMathTests
 * @notice  Mathematical tests for Router calculations
 * @dev Tests focus on decimals, precision, and complex mathematical scenarios
 */
contract RouterMathTests is FPMMBaseIntegration {
  // ============ STATE VARIABLES ============

  // Test tokens with different decimals
  MockERC20 public token18Decimals;
  MockERC20 public token6Decimals;
  MockERC20 public token8Decimals;
  MockERC20 public token12Decimals;

  // ============ SETUP ============

  function setUp() public override {
    super.setUp();

    token18Decimals = new MockERC20("Token18", "TK18", 18);
    token6Decimals = new MockERC20("Token6", "TK6", 6);
    token8Decimals = new MockERC20("Token8", "TK8", 8);
    token12Decimals = new MockERC20("Token12", "TK12", 12);
  }

  // ============ GET AMOUNTS OUT TESTS ============

  function test_getAmountsOut_whenSingleRoute_shouldCalculateCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    uint256 amountIn = 1000e18;
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    uint256 expectedAmountOut = ((amountIn * 997) / 1000) / 1e12;
    assertEq(amounts[1], expectedAmountOut);
  }

  function test_getAmountsOut_whenMultipleRoutes_shouldCalculateCorrectly() public {
    // Deploy multiple pools
    address fpmm1 = _deployFPMM(address(token18Decimals), address(token6Decimals));
    address fpmm2 = _deployFPMM(address(token6Decimals), address(token8Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm1);
    _addInitialLiquidity(address(token6Decimals), address(token8Decimals), fpmm2);

    uint256 amountIn = 1000e18;
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });
    routes[1] = IRouter.Route({ from: address(token6Decimals), to: address(token8Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 3);
    assertEq(amounts[0], amountIn);
    uint256 expectedAmountOut = ((amountIn * 997) / 1000) / 1e12;
    assertEq(amounts[1], expectedAmountOut);
    uint256 expectedAmountOut2 = ((expectedAmountOut * 997) / 1000) * 1e2;
    assertEq(amounts[2], expectedAmountOut2);
  }

  function test_getAmountsOut_whenEmptyRoutes_shouldRevert() public {
    IRouter.Route[] memory routes = new IRouter.Route[](0);

    vm.expectRevert(IRouter.InvalidPath.selector);
    router.getAmountsOut(1000e18, routes);
  }

  function test_getAmountsOut_whenDifferentOracleRates_shouldCalculateCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    // Mock different oracle rates
    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
      abi.encode(2e18, 1e18) // 2:1 rate
    );

    uint256 amountIn = 1000e18;
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    uint256 expectedAmountOut = ((amountIn * 2 * 997) / 1000) / 1e12;
    assertEq(amounts[1], expectedAmountOut);
  }

  // ============ QUOTE ADD LIQUIDITY TESTS ============

  function test_quoteAddLiquidity_whenNewPool_shouldCalculateCorrectly() public view {
    uint256 amountADesired = 1000e18;
    uint256 amountBDesired = 500e6; // 6 decimals

    (uint256 amountA, uint256 amountB, uint256 liquidity) = router.quoteAddLiquidity(
      address(token18Decimals),
      address(token6Decimals),
      address(factory),
      amountADesired,
      amountBDesired
    );

    assertEq(amountA, amountADesired);
    assertEq(amountB, amountBDesired);
    assertGt(liquidity, 0);
  }

  function test_quoteAddLiquidity_whenExistingPool_shouldCalculateCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    address token0;
    address token1;
    uint256 amount0Desired;
    uint256 amount1Desired;

    if (address(token18Decimals) < address(token6Decimals)) {
      (token0, token1) = (address(token18Decimals), address(token6Decimals));
      amount0Desired = 1000e18;
      amount1Desired = 500e6;
    } else {
      (token0, token1) = (address(token6Decimals), address(token18Decimals));
      amount0Desired = 500e6;
      amount1Desired = 1000e18;
    }

    (uint256 amount0, uint256 amount1, uint256 liquidity) = router.quoteAddLiquidity(
      token0,
      token1,
      address(factory),
      amount0Desired,
      amount1Desired
    );
    if (address(token18Decimals) < address(token6Decimals)) {
      assertEq(amount0, 500e18);
      assertEq(amount1, 500e6);
    } else {
      assertEq(amount0, 500e6);
      assertEq(amount1, 500e18);
    }
    assertEq(liquidity, 500e12);
  }

  function test_quoteAddLiquidity_whenImbalancedDesiredAmounts_shouldAdjustCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    uint256 amountADesired = 2000e18; // This should be adjusted down
    uint256 amountBDesired = 500e6;

    (uint256 amountA, uint256 amountB, uint256 liquidity) = router.quoteAddLiquidity(
      address(token18Decimals),
      address(token6Decimals),
      address(factory),
      amountADesired,
      amountBDesired
    );

    assertLt(amountA, amountADesired);
    assertEq(amountB, amountBDesired);
    assertEq(liquidity, 500e12);
  }

  // ============ QUOTE REMOVE LIQUIDITY TESTS ============

  function test_quoteRemoveLiquidity_whenExistingPool_shouldCalculateCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    uint256 liquidityToRemove = 100e12;

    (uint256 amountA, uint256 amountB) = router.quoteRemoveLiquidity(
      address(token18Decimals),
      address(token6Decimals),
      address(factory),
      liquidityToRemove
    );
    if (address(token18Decimals) < address(token6Decimals)) {
      assertEq(amountA, 100e18);
      assertEq(amountB, 100e6);
    } else {
      assertEq(amountA, 100e6);
      assertEq(amountB, 100e18);
    }
  }

  function test_quoteRemoveLiquidity_whenNonexistentPool_shouldReturnZero() public view {
    uint256 liquidityToRemove = 100e18;

    (uint256 amountA, uint256 amountB) = router.quoteRemoveLiquidity(
      address(token18Decimals),
      address(token12Decimals),
      address(factory),
      liquidityToRemove
    );

    assertEq(amountA, 0);
    assertEq(amountB, 0);
  }

  // ============ DECIMAL PRECISION TESTS ============

  function test_getAmountsOut_whenDifferentDecimals_shouldHandlePrecisionCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    uint256 amountIn = 1e18; // 1 token with 18 decimals
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    uint256 expectedAmountOut = ((amountIn * 997) / 1000) / 1e12;
    assertEq(amounts[1], expectedAmountOut);
  }

  function test_getAmountsOut_whenHighPrecisionTokens_shouldHandleCorrectly() public {
    address fpmm = _deployFPMM(address(token12Decimals), address(token8Decimals));
    _addInitialLiquidity(address(token12Decimals), address(token8Decimals), fpmm);

    uint256 amountIn = 1e8; // 1 token with 8 decimals
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(token8Decimals), to: address(token12Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    uint256 expectedAmountOut = ((amountIn * 997) / 1000) * 1e4;
    assertEq(amounts[1], expectedAmountOut);
  }

  // ============ OTHER TESTS ============

  function test_getAmountsOut_whenSmallAmount_shouldHandleCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    uint256 amountIn = 1e13; //  Small amount
    uint256 expectedAmountOut = ((amountIn * 997) / 1000) / 1e12;
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    assertEq(amounts[1], expectedAmountOut);
  }

  function test_getAmountsOut_whenVeryLargeAmount_shouldHandleCorrectly() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    uint256 amountIn = 1e30; // Large amount
    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 2);
    assertEq(amounts[0], amountIn);
    uint256 expectedAmountOut = ((amountIn * 997) / 1000) / 1e12;
    assertEq(amounts[1], expectedAmountOut);
  }

  // ============ ORACLE RATE TESTS ============

  function test_getAmountsOut_whenOracleRateChanges_shouldReflectNewRate() public {
    address fpmm = _deployFPMM(address(token18Decimals), address(token6Decimals));
    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm);

    uint256 amountIn = 1000e18;

    // First calculation with 1:1 rate
    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
      abi.encode(1e18, 1e18)
    );

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });

    uint256[] memory amounts1 = router.getAmountsOut(amountIn, routes);

    // Second calculation with 2:1 rate
    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
      abi.encode(2e18, 1e18)
    );

    uint256[] memory amounts2 = router.getAmountsOut(amountIn, routes);

    assertEq(amounts1[0], amounts2[0]); // Input amount should be same
    assertEq(amounts1[1], amounts2[1] / 2); // Output amount should be different
  }

  // ============ COMPLEX ROUTING TESTS ============

  function test_getAmountsOut_whenComplexRoute_shouldCalculateCorrectly() public {
    // Deploy multiple pools with different tokens
    address fpmm1 = _deployFPMM(address(token18Decimals), address(token6Decimals));
    address fpmm2 = _deployFPMM(address(token6Decimals), address(token8Decimals));
    address fpmm3 = _deployFPMM(address(token8Decimals), address(token12Decimals));

    _addInitialLiquidity(address(token18Decimals), address(token6Decimals), fpmm1);
    _addInitialLiquidity(address(token6Decimals), address(token8Decimals), fpmm2);
    _addInitialLiquidity(address(token8Decimals), address(token12Decimals), fpmm3);

    uint256 amountIn = 1000e18;
    IRouter.Route[] memory routes = new IRouter.Route[](3);
    routes[0] = IRouter.Route({ from: address(token18Decimals), to: address(token6Decimals), factory: address(0) });
    routes[1] = IRouter.Route({ from: address(token6Decimals), to: address(token8Decimals), factory: address(0) });
    routes[2] = IRouter.Route({ from: address(token8Decimals), to: address(token12Decimals), factory: address(0) });

    uint256[] memory amounts = router.getAmountsOut(amountIn, routes);

    assertEq(amounts.length, 4);
    assertEq(amounts[0], amountIn);
    uint256 expectedAmountOut = ((amountIn * 997) / 1000) / 1e12;
    assertEq(amounts[1], expectedAmountOut);
    uint256 expectedAmountOut2 = ((expectedAmountOut * 997) / 1000) * 1e2;
    assertEq(amounts[2], expectedAmountOut2);
    uint256 expectedAmountOut3 = ((expectedAmountOut2 * 997) / 1000) * 1e4;
    assertEq(amounts[3], expectedAmountOut3);
  }
}
