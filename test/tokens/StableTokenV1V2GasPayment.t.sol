// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { Arrays } from "../utils/Arrays.sol";
import { BaseTest } from "../utils/BaseTest.next.sol";

import { StableTokenV2 } from "contracts/tokens/StableTokenV2.sol";

import { IStableToken } from "contracts/legacy/interfaces/IStableToken.sol";
import { IFreezer } from "contracts/common/interfaces/IFreezer.sol";

contract StableTokenV1V2GasPaymentTest is BaseTest {
  StableTokenV2 tokenV2;
  IStableToken tokenV1;
  IFreezer freezer;

  address holder0 = address(0x2001);
  address holder1 = address(0x2002);
  address feeRecipient = address(0x2003);
  address gatewayFeeReceipient = address(0x2004);
  address communityFund = address(0x2005);

  function setUp() public {
    tokenV2 = new StableTokenV2(false);
    freezer = IFreezer(factory.create("Freezer", abi.encode(true)));
    tokenV1 = IStableToken(factory.create("StableToken", abi.encode(true)));

    tokenV2.initialize(
      "cUSD",
      "cUSD",
      0,
      REGISTRY_ADDRESS,
      0,
      0,
      Arrays.addresses(holder0, holder1),
      Arrays.uints(1000, 1000),
      ""
    );
    tokenV1.initialize(
      "cUSD",
      "cUSD",
      0,
      REGISTRY_ADDRESS,
      1e24,
      1 weeks,
      Arrays.addresses(holder0, holder1),
      Arrays.uints(1000, 1000),
      ""
    );

    vm.startPrank(deployer);
    registry.setAddressFor("Freezer", address(freezer));
  }

  function test_debitGasFees_whenCalledByVM_shouldBurnAmount() public {
    uint256 balanceV1Before = tokenV1.balanceOf(holder0);
    uint256 balanceV2Before = tokenV2.balanceOf(holder0);
    assertEq(balanceV1Before, 1000);
    assertEq(balanceV2Before, 1000);

    vm.startPrank(address(0));
    tokenV1.debitGasFees(holder0, 100);
    tokenV2.debitGasFees(holder0, 100);

    uint256 balanceV1After = tokenV1.balanceOf(holder0);
    uint256 balanceV2After = tokenV2.balanceOf(holder0);
    assertEq(balanceV1After, 900);
    assertEq(balanceV2After, 900);
  }

  function test_creditGasFees_whenCalledByVM_shouldCreditFees() public {
    uint256 amount = 100;
    uint256 refund = 20;
    uint256 tipTxFee = 30;
    uint256 gatewayFee = 10;
    uint256 baseTxFee = 40;

    uint256 balanceV1Before = tokenV1.balanceOf(holder0);
    uint256 balanceV2Before = tokenV2.balanceOf(holder0);
    assertEq(balanceV1Before, 1000);
    assertEq(balanceV2Before, 1000);

    vm.startPrank(address(0));
    tokenV1.debitGasFees(holder0, amount);
    tokenV1.creditGasFees(
      holder0,
      feeRecipient,
      gatewayFeeReceipient,
      communityFund,
      refund,
      tipTxFee,
      gatewayFee,
      baseTxFee
    );

    uint256 balanceV1After = tokenV1.balanceOf(holder0);
    assertEq(balanceV1After, balanceV1Before - amount + refund);
    assertEq(tokenV1.balanceOf(feeRecipient), tipTxFee);
    assertEq(tokenV1.balanceOf(gatewayFeeReceipient), gatewayFee);
    assertEq(tokenV1.balanceOf(communityFund), baseTxFee);

    tokenV2.debitGasFees(holder0, amount);
    tokenV2.creditGasFees(
      holder0,
      feeRecipient,
      gatewayFeeReceipient,
      communityFund,
      refund,
      tipTxFee,
      gatewayFee,
      baseTxFee
    );

    uint256 balanceV2After = tokenV2.balanceOf(holder0);
    assertEq(balanceV2After, balanceV2Before - amount + refund);
    assertEq(tokenV2.balanceOf(feeRecipient), tipTxFee);
    assertEq(tokenV2.balanceOf(gatewayFeeReceipient), gatewayFee);
    assertEq(tokenV2.balanceOf(communityFund), baseTxFee);
  }
}
