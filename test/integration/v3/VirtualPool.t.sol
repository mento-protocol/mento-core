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
  MentoV2Deployer,
  VirtualPoolDeployer,
  OracleAdapterDeployer,
  LiquidityStrategyDeployer,
  FPMMDeployer
{
  address internal minter = makeAddr("minter");

  function setUp() public {
    _deployTokens(false, false);
    _deployMentoV2();
    _deployOracleAdapter();
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
    vm.warp(1761645000);
  }

  function test_stable_token_v3_to_v2_swap() public {
    address user = makeAddr("user");

    vm.prank(user);
    $tokens.eurm.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.eurm.mint(user, 5_000e18);

    uint256 exofBalanceBefore = $tokens.exof.balanceOf(user);

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
  }

  function test_stable_token_v2_to_v3_swap() public {
    address user = makeAddr("user");

    vm.prank(user);
    $tokens.exof.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.exof.mint(user, 5_000e18);

    uint256 eurmBalanceBefore = $tokens.eurm.balanceOf(user);

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
  }

  function test_virtual_pool_to_virtual_pool_swap() public {
    address user = makeAddr("user");

    vm.prank(user);
    $tokens.exof.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.exof.mint(user, 5_000e18);

    uint256 celoBalanceBefore = $tokens.celo.balanceOf(user);

    vm.startPrank(user);
    IRouter.Route[] memory routes = new IRouter.Route[](2);
    routes[0] = _createVirtualRoute(address($tokens.exof), address($tokens.usdm));
    routes[1] = _createVirtualRoute(address($tokens.usdm), address($tokens.celo));

    uint256 swapAmount = 1_000e18;

    uint256 expectedUsdmOut = $virtualPool.exof_usdm_vp.getAmountOut(swapAmount, address($tokens.exof));
    uint256 expectedCeloOut = $virtualPool.usdm_celo_vp.getAmountOut(expectedUsdmOut, address($tokens.usdm));

    $fpmm.router.swapExactTokensForTokens(swapAmount, 0, routes, user, block.timestamp);
    vm.stopPrank();

    uint256 actualCeloOut = $tokens.celo.balanceOf(user) - celoBalanceBefore;
    assertEq(actualCeloOut, expectedCeloOut, "Expected CELO output should match actual output");
  }

  function test_swap_different_amounts() public {
    address user = makeAddr("user");

    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 100e18;
    amounts[1] = 1_000e18;
    amounts[2] = 10_000e18;

    vm.prank(user);
    $tokens.eurm.approve(address($fpmm.router), type(uint256).max);
    vm.prank(minter);
    $tokens.eurm.mint(user, 50_000e18);

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
  }

  function test_virtual_pool_reserves() public view {
    (uint256 r0, uint256 r1, uint256 lastUpdate) = $virtualPool.exof_usdm_vp.getReserves();

    assertGt(r0, 0, "reserve0 should be greater than 0");
    assertGt(r1, 0, "reserve1 should be greater than 0");
    assertGt(lastUpdate, 0, "lastUpdate should be greater than 0");
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
