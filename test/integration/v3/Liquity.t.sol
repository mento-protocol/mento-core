// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { console } from "forge-std/console.sol";
import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";
import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { LiquidityStrategyDeployer } from "test/integration/v3/LiquidityStrategyDeployer.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";

import { ITroveManager } from "bold/src/Interfaces/ITroveManager.sol";
import { IBorrowerOperations } from "bold/src/Interfaces/IBorrowerOperations.sol";
import { ISystemParams } from "bold/src/Interfaces/ISystemParams.sol";

contract Liquity is LiquityDeployer, OracleAdapterDeployer, LiquidityStrategyDeployer, TokenDeployer {
  function setUp() public {
    _deployTokens(false, false);
    _deployOracleAdapter();
    _deployLiquidityStrategies();
  }

  function test_deployLiquity() public {
    _deployLiquity();

    uint256 trovesCount = $liquity.troveManager.getTroveIdsCount();
    assertEq(trovesCount, 0);

    address A = makeAddr("A");
    uint256 mintAmount = 10_000e18;

    assertEq($tokens.cdpCollToken.balanceOf(A), 0);

    vm.startPrank($addresses.governance);
    $tokens.cdpCollToken.setMinter(address(this), true);
    vm.stopPrank();

    $tokens.cdpCollToken.mint(A, mintAmount);
    assertEq($tokens.cdpCollToken.balanceOf(A), mintAmount);

    console.log("> attempt to open trove");

    vm.startPrank(A);
    $tokens.cdpCollToken.approve(address($liquity.borrowerOperations), mintAmount);
    $liquity.borrowerOperations.openTrove(
      A,
      0,
      200e18,
      200e18,
      0,
      0,
      $liquity.systemParams.MIN_ANNUAL_INTEREST_RATE(),
      1000e18,
      address(0),
      address(0),
      address(0)
    );
    vm.stopPrank();

    assertEq($liquity.troveManager.getTroveIdsCount(), 1);

    console.log("troves count:", $liquity.troveManager.getTroveIdsCount());
    console.log("debt token balance of A:", $tokens.cdpDebtToken.balanceOf(A));
    console.log("gas pool balance:", $tokens.cdpCollToken.balanceOf(address($liquityInternalPools.gasPool)));
  }
}
