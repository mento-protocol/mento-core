// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { TestERC20 } from "test/utils/mocks/TestERC20.sol";

// Router contracts
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";

// Interfaces
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

// Base integration
import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";

/**
 * @title RouterZapTests
 * @notice Tests for Router zap functionality
 * @dev Tests cover zap in, zap out, and parameter generation
 */
contract RouterZapTests is FPMMBaseIntegration {
  // ============ STATE VARIABLES ============
  TestERC20 public tokenD;

  // ============ SETUP ============

  function setUp() public override {
    super.setUp();
    tokenD = new TestERC20("TokenD", "TKD");

    vm.prank(alice);
    tokenD.approve(address(router), type(uint256).max);
  }

  // ============ ZAP IN TESTS ============

  function test_zapIn_whenTokenInEqualsTokenA_shouldZapInCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm);

    vm.startPrank(alice);

    IRouter.Zap memory zapInPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    // Empty routes since tokenIn equals tokenA
    IRouter.Route[] memory routesA = new IRouter.Route[](0);
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[1], to: tokens[2], factory: address(0) });

    uint256 balanceBefore = IERC20(tokens[1]).balanceOf(alice);

    uint256 liquidity = router.zapIn(tokens[1], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    assertApproxEqRel(liquidity, 10e18, 0.01e18);
    assertEq(IERC20(tokens[1]).balanceOf(alice), balanceBefore - 20e18);

    vm.stopPrank();
  }

  function test_zapIn_whenTokenInEqualsTokenB_shouldZapInCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm);

    vm.startPrank(alice);

    IRouter.Zap memory zapInPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    // Empty routes since tokenIn equals tokenB
    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: tokens[2], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](0);

    uint256 balanceBefore = IERC20(tokens[2]).balanceOf(alice);

    uint256 liquidity = router.zapIn(tokens[2], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    assertApproxEqRel(liquidity, 10e18, 0.01e18);
    assertEq(IERC20(tokens[2]).balanceOf(alice), balanceBefore - 20e18);

    vm.stopPrank();
  }

  function test_zapIn_whenTokenInDifferentFromBothTokens_shouldZapInCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    vm.startPrank(alice);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    uint256 balanceBefore = IERC20(tokens[0]).balanceOf(alice);
    uint256 lpBalanceBefore = IERC20(fpmm).balanceOf(alice);

    uint256 liquidity = router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    assertEq(liquidity, (10e18 * 997) / 1000);
    assertEq(IERC20(tokens[0]).balanceOf(alice), balanceBefore - 20e18);
    assertEq(IERC20(fpmm).balanceOf(alice), lpBalanceBefore + (10e18 * 997) / 1000);

    vm.stopPrank();
  }

  function test_zapIn_whenInsufficientOutputAmount_shouldRevert() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm);

    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    vm.startPrank(alice);

    IRouter.Zap memory zapInPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 1000e18, // Very high minimum
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    vm.expectRevert(IRouter.InsufficientOutputAmount.selector);
    router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    vm.stopPrank();
  }

  function test_zapIn_whenInvalidRouteA_shouldRevert() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm);

    vm.startPrank(alice);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) }); // Wrong destination
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    vm.expectRevert(IRouter.InvalidRouteA.selector);
    router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    vm.stopPrank();
  }

  function test_zapIn_whenInvalidRouteB_shouldRevert() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm);

    vm.startPrank(alice);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) }); // Wrong destination

    vm.expectRevert(IRouter.InvalidRouteB.selector);
    router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    vm.stopPrank();
  }

  // ============ ZAP OUT TESTS ============

  function test_zapOut_whenTokenOutEqualsTokenA_shouldZapOutCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    // First zap in to get LP tokens
    vm.startPrank(alice);

    IERC20(fpmm).approve(address(router), type(uint256).max);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    uint256 liquidity = router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    // Now zap out to tokenA
    IRouter.Zap memory zapOutPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    // Empty routes since tokenOut equals tokenA
    IRouter.Route[] memory routesAOut = new IRouter.Route[](0);
    IRouter.Route[] memory routesBOut = new IRouter.Route[](1);
    routesBOut[0] = IRouter.Route({ from: tokens[2], to: tokens[1], factory: address(0) });

    router.zapOut(tokens[1], liquidity, zapOutPool, routesAOut, routesBOut);

    // 1000e18 initial balance + 20e18 from zaping in token0s
    uint256 expectedBalance = 1020e18;
    assertApproxEqRel(IERC20(tokens[1]).balanceOf(alice), expectedBalance, 0.01e18);
    assertEq(IERC20(fpmm).balanceOf(alice), 0);

    vm.stopPrank();
  }

  function test_zapOut_whenTokenOutEqualsTokenB_shouldZapOutCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    // First zap in to get LP tokens
    vm.startPrank(alice);

    IERC20(fpmm).approve(address(router), type(uint256).max);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    uint256 liquidity = router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    // Now zap out to tokenB
    IRouter.Zap memory zapOutPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    IRouter.Route[] memory routesAOut = new IRouter.Route[](1);
    routesAOut[0] = IRouter.Route({ from: tokens[1], to: tokens[2], factory: address(0) });
    IRouter.Route[] memory routesBOut = new IRouter.Route[](0);

    router.zapOut(tokens[2], liquidity, zapOutPool, routesAOut, routesBOut);

    // 1000e18 initial balance + 20e18 from zaping in token0s
    uint256 expectedBalance = 1020e18;
    assertApproxEqRel(IERC20(tokens[2]).balanceOf(alice), expectedBalance, 0.01e18);
    assertEq(IERC20(fpmm).balanceOf(alice), 0);

    vm.stopPrank();
  }

  function test_zapOut_whenTokenOutDifferentFromBothTokens_shouldZapOutCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    // First zap in to get LP tokens
    vm.startPrank(alice);

    IERC20(fpmm).approve(address(router), type(uint256).max);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    uint256 liquidity = router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);

    // Now zap out to token0
    IRouter.Zap memory zapOutPool = IRouter.Zap({
      tokenA: tokens[1],
      tokenB: tokens[2],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    IRouter.Route[] memory routesAOut = new IRouter.Route[](1);
    routesAOut[0] = IRouter.Route({ from: tokens[1], to: tokens[0], factory: address(0) });
    IRouter.Route[] memory routesBOut = new IRouter.Route[](1);
    routesBOut[0] = IRouter.Route({ from: tokens[2], to: tokens[0], factory: address(0) });

    router.zapOut(tokens[0], liquidity, zapOutPool, routesAOut, routesBOut);

    assertApproxEqRel(IERC20(tokens[0]).balanceOf(alice), 1000e18, 0.01e18);
    assertEq(IERC20(fpmm).balanceOf(alice), 0);

    vm.stopPrank();
  }

  // ============ PARAMETER GENERATION TESTS ============

  function test_generateZapInParams_whenValidInputs_shouldGenerateCorrectParams() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) = router.generateZapInParams(
      tokens[1],
      tokens[2],
      address(factory),
      10e18,
      10e18,
      routesA,
      routesB
    );

    assertEq(amountOutMinA, (10e18 * 997) / 1000);
    assertEq(amountOutMinB, (10e18 * 997) / 1000);
    assertEq(amountAMin, (10e18 * 997) / 1000);
    assertEq(amountBMin, (10e18 * 997) / 1000);
  }

  function test_generateZapOutParams_whenValidInputs_shouldGenerateCorrectParams() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    IRouter.Route[] memory routesA = new IRouter.Route[](1);
    routesA[0] = IRouter.Route({ from: tokens[1], to: tokens[0], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[2], to: tokens[0], factory: address(0) });

    (uint256 amountOutMinA, uint256 amountOutMinB, uint256 amountAMin, uint256 amountBMin) = router
      .generateZapOutParams(tokens[1], tokens[2], address(factory), 100e18, routesA, routesB);

    assertEq(amountOutMinA, (100e18 * 997) / 1000);
    assertEq(amountOutMinB, (100e18 * 997) / 1000);
    assertEq(amountAMin, 100e18);
    assertEq(amountBMin, 100e18);
  }

  // ============ OTHER TESTS ============

  function test_zapIn_whenVerySmallAmounts_shouldHandleCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);
    _addInitialLiquidity(tokens[0], tokens[1], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[2], fpmm3);

    vm.startPrank(alice);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    uint256 liquidity = router.zapIn(tokens[0], 1e4, 1e4, zapInPool, routesA, routesB, alice);

    assertGt(liquidity, 0);

    vm.stopPrank();
  }

  function test_zapIn_whenVeryLargeAmounts_shouldHandleCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();
    address fpmm = _deployFPMM(tokens[1], tokens[2]);
    address fpmm2 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[2]);

    _addInitialLiquidity(tokens[1], tokens[2], fpmm);

    deal(tokens[0], address(fpmm2), 1e30);
    deal(tokens[1], address(fpmm2), 1e30);
    deal(tokens[0], address(fpmm3), 1e30);
    deal(tokens[2], address(fpmm3), 1e30);

    IFPMM(fpmm2).mint(makeAddr("LP"));
    IFPMM(fpmm3).mint(makeAddr("LP"));

    // Fund with large amounts
    deal(tokens[0], alice, 1e30);

    vm.startPrank(alice);

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
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[2], factory: address(0) });

    uint256 liquidity = router.zapIn(tokens[0], 1e25, 1e25, zapInPool, routesA, routesB, alice);

    vm.stopPrank();
    assertGt(liquidity, 0);
  }

  // ============ COMPLEX ZAP SCENARIOS ============

  function test_zapIn_whenMultipleHopRoute_shouldZapInCorrectly() public {
    address[] memory tokens = _sortTokensByAddress();

    // Deploy multiple pools
    address fpmm1 = _deployFPMM(tokens[0], tokens[1]);
    address fpmm2 = _deployFPMM(tokens[1], tokens[2]);
    address fpmm3 = _deployFPMM(tokens[0], tokens[3]);
    address targetFPMM = _deployFPMM(tokens[2], tokens[3]);

    _addInitialLiquidity(tokens[0], tokens[1], fpmm1);
    _addInitialLiquidity(tokens[1], tokens[2], fpmm2);
    _addInitialLiquidity(tokens[0], tokens[3], fpmm3);
    _addInitialLiquidity(tokens[2], tokens[3], targetFPMM);

    vm.startPrank(alice);

    IRouter.Zap memory zapInPool = IRouter.Zap({
      tokenA: tokens[2],
      tokenB: tokens[3],
      factory: address(factory),
      amountOutMinA: 0,
      amountOutMinB: 0,
      amountAMin: 0,
      amountBMin: 0
    });

    // Multi-hop route: token0 -> token1 -> token2
    IRouter.Route[] memory routesA = new IRouter.Route[](2);
    routesA[0] = IRouter.Route({ from: tokens[0], to: tokens[1], factory: address(0) });
    routesA[1] = IRouter.Route({ from: tokens[1], to: tokens[2], factory: address(0) });

    IRouter.Route[] memory routesB = new IRouter.Route[](1);
    routesB[0] = IRouter.Route({ from: tokens[0], to: tokens[3], factory: address(0) });

    router.zapIn(tokens[0], 10e18, 10e18, zapInPool, routesA, routesB, alice);
    vm.stopPrank();

    // fee applied multiple times for each hop so we assume %1 variance
    assertApproxEqRel(IERC20(targetFPMM).balanceOf(alice), 10e18, .01e18);
  }
  function _sortTokensByAddress() internal view returns (address[] memory tokens) {
    tokens = new address[](4);
    tokens[0] = address(tokenA);
    tokens[1] = address(tokenB);
    tokens[2] = address(tokenC);
    tokens[3] = address(tokenD);
  }
}
