// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { LiquityDeployer } from "test/integration/v3/LiquityDeployer.sol";

import { Test, console2 as console } from "forge-std/Test.sol";

import { StableTokenV3 } from "contracts/tokens/StableTokenV3.sol";

import { IBoldToken, IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

contract Liquity is LiquityDeployer, TokenDeployer {
  LiquityDeployer deployer;
  IBoldToken public debtToken;
  IERC20Metadata public collateralToken;

  function setUp() public {
    _deployCollateralToken("Mento USD", "USD.m", 18);
    _deployDebtToken("Celo Euro", "cEUR");
  }

  function test_deployLiquity() public {
    console.log("-- Deploying Liquity --");

    LiquityContractsDev memory contracts = deploy();

    $liquity.addressesRegistry = contracts.addressesRegistry;
    $liquity.borrowerOperations = contracts.borrowerOperations;
    $liquity.sortedTroves = contracts.sortedTroves;
    $liquity.activePool = contracts.activePool;
    $liquity.stabilityPool = contracts.stabilityPool;
    $liquity.troveManager = contracts.troveManager;
    $liquity.troveNFT = contracts.troveNFT;
    $liquity.priceFeed = contracts.priceFeed;
    $liquity.interestRouter = contracts.interestRouter;
    $liquity.collToken = contracts.collToken;
    $liquity.systemParams = contracts.systemParams;

    printTokenAddresses();

    printLiquityAddresses();
  }
}
