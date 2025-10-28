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
