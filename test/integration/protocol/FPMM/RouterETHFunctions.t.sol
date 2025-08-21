// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

// Router contracts
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";

// Base integration
import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";

// Interfaces
import { IERC20 } from "contracts/interfaces/IERC20.sol";

/**
 * @title RouterETHFunctionsTest
 * @notice Tests for Router ETH-related functions that should revert on Celo
 * @dev These functions should revert because Celo doesn't have native ETH handling
 */
contract RouterETHFunctionsTest is FPMMBaseIntegration {
  // ============ STATE VARIABLES ============

  // ============ SETUP ============

  function setUp() public override {
    super.setUp();
  }

  // ============ ETH-RELATED FUNCTION TESTS ============

  function test_addLiquidityETH_whenCalled_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.startPrank(alice);
    vm.deal(alice, 1e18);

    // This should revert because Celo doesn't support native ETH
    vm.expectRevert(IRouter.PoolDoesNotExist.selector);
    router.addLiquidityETH{ value: 1e18 }(
      address(tokenA),
      100e18, // amountTokenDesired
      0, // amountTokenMin
      0, // amountETHMin
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_removeLiquidityETH_whenCalled_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    // Add some liquidity first (this will also revert, but we're testing the remove function)
    vm.startPrank(alice);
    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.removeLiquidityETH(
      address(tokenA),
      100e18, // liquidity
      0, // amountTokenMin
      0, // amountETHMin
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_removeLiquidityETHSupportingFeeOnTransferTokens_whenCalled_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.startPrank(alice);
    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.removeLiquidityETHSupportingFeeOnTransferTokens(
      address(tokenA),
      100e18, // liquidity
      0, // amountTokenMin
      0, // amountETHMin
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_swapExactETHForTokens_whenCalled_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.swapExactETHForTokens{ value: 1e18 }(
      0, // amountOutMin
      routes,
      alice,
      block.timestamp
    );
  }

  function test_swapExactTokensForETH_whenCalled_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.startPrank(alice);

    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.swapExactTokensForETH(
      10e18, // amountIn
      0, // amountOutMin
      routes,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_swapExactETHForTokensSupportingFeeOnTransferTokens_whenCalled_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: 1e18 }(
      0, // amountOutMin
      routes,
      alice,
      block.timestamp
    );
  }

  function test_swapExactTokensForETHSupportingFeeOnTransferTokens_whenCalled_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = IRouter.Route({ from: address(tokenA), to: address(tokenB), factory: address(0) });

    vm.startPrank(alice);

    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      10e18, // amountIn
      0, // amountOutMin
      routes,
      alice,
      block.timestamp
    );

    vm.stopPrank();
  }

  function test_zapIn_whenTokenInIsETHER_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    IRouter.Zap memory zapInPool = IRouter.Zap({
      tokenA: address(tokenA),
      tokenB: address(tokenB),
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: address(weth), to: address(tokenA), factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: address(weth), to: address(tokenB), factory: address(0) });
    address e = router.ETHER();
    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.zapIn{ value: 1e18 }(
      e, // tokenIn is ETHER
      0.5e18, // amountInA
      0.5e18, // amountInB
      zapInPool,
      routesA,
      routesB,
      alice
    );
  }

  function test_zapOut_whenTokenOutIsETHER_shouldRevert() public {
    address fpmm = _deployFPMM(address(tokenA), address(tokenB));
    _addInitialLiquidity(address(tokenA), address(tokenB), fpmm);

    vm.prank(makeAddr("LP"));
    IERC20(fpmm).transfer(address(alice), 100e18);

    vm.startPrank(alice);

    IERC20(fpmm).approve(address(router), type(uint256).max);

    IRouter.Zap memory zapOutPool = IRouter.Zap({
      tokenA: address(tokenA),
      tokenB: address(tokenB),
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: address(tokenA), to: address(weth), factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: address(tokenB), to: address(weth), factory: address(0) });

    address e = router.ETHER();
    // This should revert because Celo doesn't support native ETH
    vm.expectRevert();
    router.zapOut(
      e, // tokenOut is ETHER
      10e18, // liquidity
      zapOutPool,
      routesA,
      routesB
    );

    vm.stopPrank();
  }

  function test_receive_whenCalledByNonWETH_shouldRevert() public {
    // Test that the receive function reverts when called by non-WETH
    vm.expectRevert(IRouter.OnlyWETH.selector);
    address(router).call{ value: 1e18 }("");
  }

  function test_ETHER_constant_shouldReturnCorrectAddress() public {
    // Test that the ETHER constant returns the expected address
    assertEq(router.ETHER(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  }
}
