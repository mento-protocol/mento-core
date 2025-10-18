// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";

import { Test, console2 as console } from "forge-std/Test.sol";

import { StableTokenV3 } from "contracts/tokens/StableTokenV3.sol";

import { IBoldToken, IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IMockFXPriceFeed } from "bold/test/TestContracts/Interfaces/IMockFXPriceFeed.sol";
import { ITroveManager } from "bold/src/Interfaces/ITroveManager.sol";
import { IBorrowerOperations } from "bold/src/Interfaces/IBorrowerOperations.sol";
import { ISystemParams } from "bold/src/Interfaces/ISystemParams.sol";

contract Liquity is LiquityDeployer, TokenDeployer {
  function setUp() public {
    _deployCollateralToken("Mento USD", "USD.m", 18);
    _deployDebtToken("Celo Euro", "cEUR");
  }

  function test_deployLiquity() public {
    _deployLiquity();

    IMockFXPriceFeed feed = IMockFXPriceFeed(address($liquity.priceFeed));
    ITroveManager troveManager = ITroveManager(address($liquity.troveManager));
    MockERC20 collateralToken = MockERC20(address($tokens.collateralToken));
    IBorrowerOperations borrowerOperations = IBorrowerOperations(address($liquity.borrowerOperations));
    ISystemParams systemParams = ISystemParams(address($liquity.systemParams));

    feed.setPrice(2000e18);
    uint256 trovesCount = troveManager.getTroveIdsCount();
    assertEq(trovesCount, 0);

    address A = makeAddr("A");
    uint256 mintAmount = 10_000e18;
    assertEq(collateralToken.balanceOf(A), 0);
    collateralToken.mint(A, mintAmount);
    assertEq(collateralToken.balanceOf(A), mintAmount);

    console.log("> attempt to open trove");

    vm.startPrank(A);
    collateralToken.approve(address(borrowerOperations), mintAmount);
    borrowerOperations.openTrove(
      A,
      0,
      2e18,
      2000e18,
      0,
      0,
      systemParams.MIN_ANNUAL_INTEREST_RATE(),
      1000e18,
      address(0),
      address(0),
      address(0)
    );
    vm.stopPrank();

    assertEq(troveManager.getTroveIdsCount(), 1);

    console.log("troves count:", troveManager.getTroveIdsCount());
    console.log("debt token balance of A:", $tokens.debtToken.balanceOf(A));
    console.log("gas pool balance:", collateralToken.balanceOf(address($liquityInternalPools.gasPool)));
  }
}
