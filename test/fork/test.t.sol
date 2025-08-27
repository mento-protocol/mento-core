// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ICollateralRegistry } from "contracts/v3/interfaces/ICollateralRegistry.sol";
import { IBoldToken } from "contracts/v3/interfaces/IBoldToken.sol";
import { console } from "forge-std/console.sol";

contract RedemptionCalculatorTest is Test {
  IERC20 public bolt = IERC20(0x6440f144b7e50D6a8439336510312d2F54beB01D);
  ICollateralRegistry public collateralRegistry = ICollateralRegistry(0xf949982B91C8c61e952B3bA942cbbfaef5386684);

  function setUp() public {
    vm.createSelectFork("https://eth.llamarpc.com");
  }

  function testRedemptionFeeCalc() public {
    uint256 amountToRedeem = 100_000 * 1e18;
    uint256 supply = bolt.totalSupply();
    uint256 expectedFee = collateralRegistry.getRedemptionRateForRedeemedAmount(amountToRedeem);

    uint256 decayedBaseFee = collateralRegistry.getRedemptionRateWithDecay();

    uint256 calculatedFee = decayedBaseFee + ((amountToRedeem * 1e18) / supply);

    uint256 expectedAmount = (supply * (expectedFee - decayedBaseFee)) / 1e18;

    console.log("expectedFee", expectedFee);
    console.log("calculatedFee", calculatedFee);
    console.log("expectedAmount", expectedAmount);
  }
}
