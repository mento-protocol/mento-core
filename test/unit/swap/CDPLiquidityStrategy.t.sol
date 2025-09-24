// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { CDPLiquidityStrategy } from "contracts/v3/CDPLiquidityStrategy.sol";
import { CDPPolicy } from "contracts/v3/CDPPolicy.sol";
import { LiquidityTypes as LQ } from "contracts/v3/libraries/LiquidityTypes.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { LiquidityController } from "contracts/v3/LiquidityController.sol";

import { console } from "forge-std/console.sol";

contract CDPLiquidityStrategyTest is Test {
  CDPLiquidityStrategy public cdpLiquidityStrategy;
  CDPPolicy public cdpPolicy;
  FPMM public fpmm;
  LiquidityController public liquidityController;
  address public liquiditySource;
  address public debtToken;
  address public collToken;
  address public sortedOracles = makeAddr("sortedOracles");
  address public referenceRateFeedID = makeAddr("referenceRateFeedID");
  address public breakerBox = makeAddr("breakerBox");
  address public stabilityPool = makeAddr("stabilityPool");
  address public collateralRegistry = makeAddr("collateralRegistry");

  function setUp() public {
    debtToken = address(new MockERC20("debtToken", "DT", 18));
    collToken = address(new MockERC20("collToken", "CT", 6));
    cdpLiquidityStrategy = new CDPLiquidityStrategy(true);
    fpmm = new FPMM(false);
    fpmm.initialize(debtToken, collToken, sortedOracles, referenceRateFeedID, false, breakerBox, address(this));

    address[] memory debtTokens = new address[](1);
    address[] memory stabilityPools = new address[](1);
    address[] memory collateralRegistries = new address[](1);
    uint256[] memory redemptionBetas = new uint256[](1);
    debtTokens[0] = debtToken;
    stabilityPools[0] = stabilityPool;
    collateralRegistries[0] = collateralRegistry;
    redemptionBetas[0] = 1;
    cdpPolicy = new CDPPolicy(debtTokens, stabilityPools, collateralRegistries, redemptionBetas);
    liquidityController = new LiquidityController();
    liquidityController.initialize(address(this));
  }

  function test_setup() public {
    console.log("debtToken", debtToken);
  }
}
