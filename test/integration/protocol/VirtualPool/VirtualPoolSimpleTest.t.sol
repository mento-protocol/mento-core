// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { VirtualPoolBaseIntegration } from "./VirtualPoolBaseIntegration.t.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { IRPool } from "contracts/swap/router/interfaces/IRPool.sol";

contract VirtualPoolSimpleTest is VirtualPoolBaseIntegration {
  function test_deployVirtualPool_shouldWork() public {
    address celoToCUSD = _deployFPMM(address(celoToken), address(cUSDToken), cUSD_CELO_referenceRateFeedID);
    _addInitialLiquidity(address(celoToken), address(cUSDToken), celoToCUSD);

    IRPool pool = IRPool(vpFactory.deployVirtualPool(address(broker), address(biPoolManager), pair_cUSD_cEUR_ID));

    assert(vpFactory.isPool(address(pool)));

    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createV3Route(address(celoToken), address(cUSDToken));
    routes[1] = _createVirtualRoute(address(cUSDToken), address(cEURToken));

    uint256 amountIn = 10e18;
    uint256 amountOutHop1 = IRPool(celoToCUSD).getAmountOut(amountIn, address(celoToken));
    uint256 expectedAmountOut = pool.getAmountOut(amountOutHop1, address(cUSDToken));

    vm.startPrank(alice);

    uint256 balanceBefore = cEURToken.balanceOf(alice);

    router.swapExactTokensForTokens(amountIn, 0, routes, alice, block.timestamp);

    uint256 balanceAfter = cEURToken.balanceOf(alice);
    assertEq(balanceAfter - balanceBefore, expectedAmountOut);
    assertEq(celoToken.balanceOf(alice), 1000e18 - amountIn);

    vm.stopPrank();
  }
}
