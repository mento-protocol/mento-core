// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { TestSetup } from "./TestSetup.sol";

contract EmissionTest is TestSetup {
  uint256 public constant NEGLIGIBLE_AMOUNT = 2e18;

  function test_constructor_shouldSetOwner() public {
    assertEq(emission.owner(), OWNER);
  }

  function test_setToken_whenNoOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    emission.setTokenContract(address(mentoToken));
  }

  function test_setToken_whenOwner_shouldSetTokenAddress() public {
    vm.prank(OWNER);
    emission.setTokenContract(address(mentoToken));

    assertEq(address(emission.mentoToken()), address(mentoToken));
  }

  function test_setEmissionTarget_whenNoOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    emission.setEmissionTarget(TREASURY_CONTRACT);
  }

  function test_setEmissionTarget_whenOwner_shouldSetEmissionTargetAddress() public {
    vm.prank(OWNER);
    emission.setEmissionTarget(TREASURY_CONTRACT);

    assertEq(emission.emissionTarget(), TREASURY_CONTRACT);
  }

  function test_transferOwnership_whenNoOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    emission.transferOwnership(ALICE);
  }

  function test_transferOwnership_whenOwner_shouldSetNewOwner() public {
    vm.prank(OWNER);
    emission.transferOwnership(ALICE);

    assertEq(emission.owner(), ALICE);
  }

  function test_renounceOwnership_whenOwner_shouldRemoveOwner() public {
    vm.prank(OWNER);
    emission.renounceOwnership();

    assertEq(emission.owner(), address(0));
  }

  function test_emitTokens_whenAfter1Month_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor1Month = EMISSION_SUPPLY - 646307413430992875884118016;
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();

    vm.warp(30 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);
  }

  function test_emitTokens_whenAfter6Months_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor6Months = 21_843_234_063015835240235008;
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();

    vm.warp(6 * 30 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor6Months, NEGLIGIBLE_AMOUNT);
  }

  function test_emitTokens_whenAfter1Year_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor1Year = 43_528_546_933402472967831552;
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();

    vm.warp(365 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Year, NEGLIGIBLE_AMOUNT);
  }

  function test_emitTokens_whenAfter10Years_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor10Years = 324_224_324_552724462524432384;
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();

    vm.warp(10 * 365 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor10Years, NEGLIGIBLE_AMOUNT);
  }

  function test_emitTokens_whenAfter15Years_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor15Years = 414_599_716_906924316446162944;
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();

    vm.warp(15 * 365 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor15Years, NEGLIGIBLE_AMOUNT);
  }

  // Note: It does not work after 50 years
  function test_emitTokens_whenAfter25Years_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor25Years = 469_947_278_142279263579013120;
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();

    vm.warp(25 * 365 days);
    uint256 amount = emission.emitTokens();
    assertApproxEqAbs(amount, calculatedAmountFor25Years, NEGLIGIBLE_AMOUNT);
  }
  // TODO: Fuzz tests
  // TODO: What about longer periods like 30 years?
}
