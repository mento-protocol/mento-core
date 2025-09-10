// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { VirtualPoolBaseIntegration } from "./VirtualPoolBaseIntegration.t.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { IRPool } from "contracts/swap/router/interfaces/IRPool.sol";

contract VirtualPoolSimpleTest is VirtualPoolBaseIntegration {
  IRPool public fpmm;
  IRPool public cUSD_cEUR_vp;
  IRPool public cUSD_celo_vp;

  function setUp() public override {
    super.setUp();

    fpmm = IRPool(_deployFPMM(address(celoToken), address(cUSDToken), cUSD_CELO_referenceRateFeedID));
    _addInitialLiquidity(address(celoToken), address(cUSDToken), address(fpmm));

    cUSD_cEUR_vp = IRPool(vpFactory.deployVirtualPool(address(broker), address(biPoolManager), pair_cUSD_cEUR_ID));
    cUSD_celo_vp = IRPool(vpFactory.deployVirtualPool(address(broker), address(biPoolManager), pair_cUSD_CELO_ID));
  }

  function test_mixedSwapRoutesV3V2_shouldWork() public {
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createV3Route(address(celoToken), address(cUSDToken));
    routes[1] = _createVirtualRoute(address(cUSDToken), address(cEURToken));

    uint256 amountIn = 10e18;
    uint256 amountOutHop1 = fpmm.getAmountOut(amountIn, address(celoToken));
    uint256 expectedAmountOut = cUSD_cEUR_vp.getAmountOut(amountOutHop1, address(cUSDToken));

    vm.startPrank(alice);

    uint256 balanceBefore = cEURToken.balanceOf(alice);

    router.swapExactTokensForTokens(amountIn, 0, routes, alice, block.timestamp);

    uint256 balanceAfter = cEURToken.balanceOf(alice);
    assertEq(balanceAfter - balanceBefore, expectedAmountOut);
    assertEq(celoToken.balanceOf(alice), 1000e18 - amountIn);

    vm.stopPrank();
  }

  function test_mixedSwapRoutesV3V2_whenAmountOutMinIsntMet_shouldRevert() public {
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createV3Route(address(celoToken), address(cUSDToken));
    routes[1] = _createVirtualRoute(address(cUSDToken), address(cEURToken));

    uint256 amountIn = 10e18;
    uint256 amountOutHop1 = fpmm.getAmountOut(amountIn, address(celoToken));
    uint256 expectedAmountOut = cUSD_cEUR_vp.getAmountOut(amountOutHop1, address(cUSDToken));

    vm.startPrank(alice);

    vm.expectRevert(IRouter.InsufficientOutputAmount.selector);
    router.swapExactTokensForTokens(amountIn, expectedAmountOut + 1, routes, alice, block.timestamp);

    vm.stopPrank();
  }

  function test_mixedSwapRoutesV2V3_shouldWork() public {
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createVirtualRoute(address(cEURToken), address(cUSDToken));
    routes[1] = _createV3Route(address(cUSDToken), address(celoToken));

    uint256 amountIn = 10e18;
    uint256 amountOutHop1 = cUSD_cEUR_vp.getAmountOut(amountIn, address(cEURToken));
    uint256 expectedAmountOut = fpmm.getAmountOut(amountOutHop1, address(cUSDToken));

    vm.startPrank(charlie);

    uint256 balanceBefore = celoToken.balanceOf(charlie);

    router.swapExactTokensForTokens(amountIn, 0, routes, charlie, block.timestamp);

    uint256 balanceAfter = celoToken.balanceOf(charlie);
    assertEq(balanceAfter - balanceBefore, expectedAmountOut);
    assertEq(cEURToken.balanceOf(charlie), 1000e18 - amountIn);

    vm.stopPrank();
  }

  function test_mixedSwapRoutesV2V3_whenAmountOutMinIsntMet_shouldRevert() public {
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createVirtualRoute(address(cEURToken), address(cUSDToken));
    routes[1] = _createV3Route(address(cUSDToken), address(celoToken));

    uint256 amountIn = 10e18;
    uint256 amountOutHop1 = cUSD_cEUR_vp.getAmountOut(amountIn, address(cEURToken));
    uint256 expectedAmountOut = fpmm.getAmountOut(amountOutHop1, address(cUSDToken));

    vm.startPrank(charlie);

    vm.expectRevert(IRouter.InsufficientOutputAmount.selector);
    router.swapExactTokensForTokens(amountIn, expectedAmountOut + 1, routes, charlie, block.timestamp);

    vm.stopPrank();
  }

  function test_multiHopSwapV2V2_shouldWork() public {
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createVirtualRoute(address(cEURToken), address(cUSDToken));
    routes[1] = _createVirtualRoute(address(cUSDToken), address(celoToken));

    uint256 amountIn = 10e18;
    uint256 amountOutHop1 = cUSD_cEUR_vp.getAmountOut(amountIn, address(cEURToken));
    uint256 expectedAmountOut = cUSD_celo_vp.getAmountOut(amountOutHop1, address(cUSDToken));

    vm.startPrank(charlie);

    uint256 balanceBefore = celoToken.balanceOf(charlie);

    router.swapExactTokensForTokens(amountIn, 0, routes, charlie, block.timestamp);

    uint256 balanceAfter = celoToken.balanceOf(charlie);
    assertEq(balanceAfter - balanceBefore, expectedAmountOut);
    assertEq(cEURToken.balanceOf(charlie), 1000e18 - amountIn);

    vm.stopPrank();
  }
}
