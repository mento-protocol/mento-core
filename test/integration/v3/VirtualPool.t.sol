// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { MentoV2Deployer } from "test/integration/v3/MentoV2Deployer.sol";
import { VirtualPoolDeployer } from "test/integration/v3/VirtualPoolDeployer.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";

contract VirtualPoolTest is
  TokenDeployer,
  VirtualPoolDeployer,
  OracleAdapterDeployer,
  MentoV2Deployer,
  LiquidityStrategyDeployer,
  FPMMDeployer
{
  address internal minter = makeAddr("minter");

  function setUp() public {
    _deployTokens(false, false);
    _deployOracleAdapter();
    _deployMentoV2();
    _deployLiquidityStrategies();
    _deployFPMM(false, false);
    _initializeV3($tokens.eurm);
    _initializeV3($tokens.usdm);
    _deployVirtualPools();
    vm.startPrank($addresses.governance);
    $tokens.eurm.setMinter(minter, true);
    $tokens.usdm.setMinter(minter, true);
    $tokens.exof.setValidators(minter);
    vm.stopPrank();
    vm.startPrank(minter);
    IStableTokenV3(address($tokens.celo)).mint(address($mentoV2.reserve), 50_000_000e18);
    $tokens.usdm.mint(address($mentoV2.reserve), 50_000_000e18);
    $tokens.usdm.mint(minter, 50_000_000e18);
    $tokens.eurm.mint(minter, 50_000_000e18);
    vm.stopPrank();
    _provideLiquidityToFPMM($fpmm.fpmmCDP, minter, 50_000_000e18, 50_000_000e18);
  }

  function test_stableTokenV3ToV2_swap() public {
    address user = makeAddr("user");
    _reportReserveFPMMRate(1e24);

    vm.prank(user);
    $tokens.eurm.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.eurm.mint(user, 5_000e18);

    uint256 exofBalanceBefore = $tokens.exof.balanceOf(user);
    uint256 eurmBalanceBefore = $tokens.eurm.balanceOf(user);

    vm.startPrank(user);
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createV3Route(address($tokens.eurm), address($tokens.usdm));
    routes[1] = _createVirtualRoute(address($tokens.usdm), address($tokens.exof));

    uint256 swapAmount = 1_000e18;

    uint256 expectedUsdmOut = $fpmm.fpmmCDP.getAmountOut(swapAmount, address($tokens.eurm));
    uint256 expectedExofOut = $virtualPool.exof_usdm_vp.getAmountOut(expectedUsdmOut, address($tokens.usdm));

    $fpmm.router.swapExactTokensForTokens(swapAmount, 0, routes, user, block.timestamp);
    vm.stopPrank();

    uint256 actualExofOut = $tokens.exof.balanceOf(user) - exofBalanceBefore;
    assertEq(actualExofOut, expectedExofOut, "Expected eXOF output should match actual output");
    assertEq(
      $tokens.eurm.balanceOf(user),
      eurmBalanceBefore - swapAmount,
      "EUR.m balance should decrease by swap amount"
    );
  }

  function test_stableTokenV2ToV3_swap() public {
    address user = makeAddr("user");

    vm.prank(user);
    $tokens.exof.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.exof.mint(user, 5_000e18);

    uint256 eurmBalanceBefore = $tokens.eurm.balanceOf(user);
    uint256 exofBalanceBefore = $tokens.exof.balanceOf(user);

    vm.startPrank(user);
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createVirtualRoute(address($tokens.exof), address($tokens.usdm));
    routes[1] = _createV3Route(address($tokens.usdm), address($tokens.eurm));

    uint256 swapAmount = 1_000e18;

    uint256 expectedUsdmOut = $virtualPool.exof_usdm_vp.getAmountOut(swapAmount, address($tokens.exof));
    uint256 expectedEurmOut = $fpmm.fpmmCDP.getAmountOut(expectedUsdmOut, address($tokens.usdm));

    $fpmm.router.swapExactTokensForTokens(swapAmount, 0, routes, user, block.timestamp);
    vm.stopPrank();

    uint256 actualEurmOut = $tokens.eurm.balanceOf(user) - eurmBalanceBefore;
    assertEq(actualEurmOut, expectedEurmOut, "Expected EUR.m output should match actual output");
    assertEq(
      $tokens.exof.balanceOf(user),
      exofBalanceBefore - swapAmount,
      "eXOF balance should decrease by swap amount"
    );
  }

  function test_stableTokenV3ToV2ThreeHops_swap() public {
    address user = makeAddr("user");

    vm.prank(user);
    $tokens.eurm.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.eurm.mint(user, 5_000e18);

    vm.startPrank(user);
    IRouter.Route[] memory routes = new IRouter.Route[](3);
    routes[0] = _createV3Route(address($tokens.eurm), address($tokens.usdm));
    routes[1] = _createVirtualRoute(address($tokens.usdm), address($tokens.exof));
    routes[2] = _createVirtualRoute(address($tokens.exof), address($tokens.celo));

    uint256 eurmBalanceBefore = $tokens.eurm.balanceOf(user);

    uint256 swapAmount = 2_500e18;

    uint256 expectedUsdmOut = $fpmm.fpmmCDP.getAmountOut(swapAmount, address($tokens.eurm));
    uint256 expectedExofOut = $virtualPool.exof_usdm_vp.getAmountOut(expectedUsdmOut, address($tokens.usdm));
    uint256 expectedCeloOut = $virtualPool.exof_celo_vp.getAmountOut(expectedExofOut, address($tokens.exof));

    $fpmm.router.swapExactTokensForTokens(swapAmount, 0, routes, user, block.timestamp);
    vm.stopPrank();

    assertEq(expectedCeloOut, $tokens.celo.balanceOf(user));
    assertEq(
      $tokens.eurm.balanceOf(user),
      eurmBalanceBefore - swapAmount,
      "EUR.m balance should decrease by swap amount"
    );
  }

  function test_virtualPoolToVirtualPool_swap() public {
    address user = makeAddr("user");

    vm.prank(user);
    $tokens.usdm.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.usdm.mint(user, 5_000e18);

    uint256 celoBalanceBefore = $tokens.celo.balanceOf(user);
    uint256 usdmBalanceBefore = $tokens.usdm.balanceOf(user);

    vm.startPrank(user);
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createVirtualRoute(address($tokens.usdm), address($tokens.exof));
    routes[1] = _createVirtualRoute(address($tokens.exof), address($tokens.celo));

    uint256 swapAmount = 1_000e18;

    uint256 expectedExofOut = $virtualPool.exof_usdm_vp.getAmountOut(swapAmount, address($tokens.usdm));
    uint256 expectedCeloOut = $virtualPool.exof_celo_vp.getAmountOut(expectedExofOut, address($tokens.exof));

    $fpmm.router.swapExactTokensForTokens(swapAmount, 0, routes, user, block.timestamp);
    vm.stopPrank();

    uint256 actualCeloOut = $tokens.celo.balanceOf(user) - celoBalanceBefore;
    assertEq(actualCeloOut, expectedCeloOut, "Expected CELO output should match actual output");
    assertEq(
      $tokens.usdm.balanceOf(user),
      usdmBalanceBefore - swapAmount,
      "USD.m balance should decrease by swap amount"
    );
  }

  function test_swapDifferentAmounts_swap() public {
    address user = makeAddr("user");

    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 100e18;
    amounts[1] = 1_000e18;
    amounts[2] = 10_000e18;

    vm.prank(user);
    $tokens.eurm.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.eurm.mint(user, 50_000e18);

    uint256 eurmBalanceBefore = $tokens.eurm.balanceOf(user);

    for (uint256 i = 0; i < amounts.length; i++) {
      uint256 swapAmount = amounts[i];

      uint256 exofBalanceBefore = $tokens.exof.balanceOf(user);

      vm.startPrank(user);
      IRouter.Route[] memory routes = new IRouter.Route[](2);
      routes[0] = _createV3Route(address($tokens.eurm), address($tokens.usdm));
      routes[1] = _createVirtualRoute(address($tokens.usdm), address($tokens.exof));

      uint256 expectedUsdmOut = $fpmm.fpmmCDP.getAmountOut(swapAmount, address($tokens.eurm));
      uint256 expectedExofOut = $virtualPool.exof_usdm_vp.getAmountOut(expectedUsdmOut, address($tokens.usdm));

      $fpmm.router.swapExactTokensForTokens(swapAmount, 0, routes, user, block.timestamp);
      vm.stopPrank();

      uint256 actualExofOut = $tokens.exof.balanceOf(user) - exofBalanceBefore;
      assertEq(actualExofOut, expectedExofOut, "Expected eXOF output should match actual output");
    }
    assertEq(
      $tokens.eurm.balanceOf(user),
      eurmBalanceBefore - amounts[0] - amounts[1] - amounts[2],
      "EUR.m balance should decrease by total swap amounts"
    );
  }

  function test_swapToNonExistentPools_shouldRevert() public {
    address user = makeAddr("user");
    vm.prank(user);
    $tokens.eurm.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.eurm.mint(user, 5_000e18);

    IRouter.Route[] memory routes = new IRouter.Route[](1);
    routes[0] = _createV3Route(address($tokens.eurm), address($tokens.exof));

    vm.expectRevert(IRouter.PoolDoesNotExist.selector);
    $fpmm.router.swapExactTokensForTokens(1_000e18, 0, routes, user, block.timestamp);

    routes[0] = _createVirtualRoute(address($tokens.eurm), address($tokens.exof));
    vm.expectRevert(IRouter.PoolDoesNotExist.selector);
    $fpmm.router.swapExactTokensForTokens(1_000e18, 0, routes, user, block.timestamp);
  }

  function _createV3Route(address from, address to) internal view returns (IRouter.Route memory) {
    return IRouter.Route({ from: from, to: to, factory: address($fpmm.fpmmFactory) });
  }

  function _createVirtualRoute(address from, address to) internal view returns (IRouter.Route memory) {
    return IRouter.Route({ from: from, to: to, factory: address($virtualPool.factory) });
  }

  function _initializeV3(IStableTokenV3 token) internal {
    vm.startPrank($addresses.governance);
    token.setMinter(address($mentoV2.broker), true);
    token.setBurner(address($mentoV2.broker), true);
    vm.stopPrank();
  }
}
