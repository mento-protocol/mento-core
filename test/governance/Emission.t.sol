// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { TestSetup } from "./TestSetup.sol";

contract EmissionTest is TestSetup {
  uint256 public constant INITIAL_TREASURY_BALANCE = 100_000_000 * 1e18;
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
    _setupEmissionContract();
    uint256 calculatedAmountFor1Month = 3_692_586_569007124115881984;

    vm.warp(30 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter6Months_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor6Months = 21_843_234_063015835240235008;

    vm.warp(6 * 30 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor6Months, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter1Year_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor1Year = 43_528_546_933402472967831552;

    vm.warp(365 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Year, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter10Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor10Years = 324_224_324_552724462524432384;

    vm.warp(10 * 365 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor10Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter15Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor15Years = 414_599_716_906924316446162944;

    vm.warp(15 * 365 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor15Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  // Note: It does not work after 50 years
  function test_emitTokens_whenAfter25Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor25Years = 469_947_278_142279263579013120;

    vm.warp(25 * 365 days);
    uint256 amount = emission.emitTokens();
    assertApproxEqAbs(amount, calculatedAmountFor25Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_fuzz_emitTokens_shouldNotRevert(uint256 timePassed) public {
    _setupEmissionContract();

    vm.assume(timePassed < 40 * 365 days);
    vm.assume(timePassed > 1 hours);

    vm.warp(timePassed);
    uint256 amount = emission.emitTokens();

    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenMultipleEmits_shouldTakePreviousMintsIntoAccount() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor1Month = 3_692_586_569007124115881984;
    uint256 calculatedAmountFor1Year = 43_528_546_933402472967831552;

    vm.warp(30 days);
    emission.emitTokens();

    assertApproxEqAbs(emission.emittedAmount(), calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);

    vm.warp(365 days);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Year - calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);
    assertApproxEqAbs(emission.emittedAmount(), calculatedAmountFor1Year, NEGLIGIBLE_AMOUNT);
  }

  function test_fuzz_emitTokens_whenMultipleEmits_shouldNotRevert(
    uint256 duration1,
    uint256 duration2,
    uint256 duration3
  ) public {
    _setupEmissionContract();

    // using duration as days to avoid "cheatcode rejected too many inputs" error
    vm.assume(duration1 < 10 * 365);
    vm.assume(duration2 < 10 * 365);
    vm.assume(duration3 < 10 * 365);

    vm.assume(duration1 > 0);
    vm.assume(duration2 > 0);
    vm.assume(duration3 > 0);

    vm.warp(duration1 * 1 days);
    uint256 amount1 = emission.emitTokens();

    vm.warp(duration1 * 1 days + duration2 * 1 days);
    uint256 amount2 = emission.emitTokens();

    vm.warp(duration1 * 1 days + duration2 * 1 days + duration3 * 1 days);
    uint256 amount3 = emission.emitTokens();

    uint256 totalEmitted = amount1 + amount2 + amount3;

    assertEq(totalEmitted, emission.emittedAmount());
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), totalEmitted + INITIAL_TREASURY_BALANCE);
  }

  function _setupEmissionContract() internal {
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();
  }
}
