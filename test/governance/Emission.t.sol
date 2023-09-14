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
    uint256 calculatedAmountFor1Month = 3_692_586_569039559708901376;

    vm.warp(MONTH);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter6Months_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor6Months = 21_843_234_315804553582215168;

    vm.warp(6 * MONTH);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor6Months, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter1Year_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor1Year = 43_528_555_600215261579313152;

    vm.warp(YEAR);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Year, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter10Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor10Years = 325_091_005_832242294004121600;

    vm.warp(10 * YEAR);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor10Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter15Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor15Years = 421_181_077_873262995273940992;

    vm.warp(15 * YEAR);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor15Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter25Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor25Years = 554_584_121_845194220594266112;

    vm.warp(25 * YEAR);
    uint256 amount = emission.emitTokens();
    assertApproxEqAbs(amount, calculatedAmountFor25Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter30Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor30Years = 624_618_096_854971046875365376;

    vm.warp(30 * YEAR);
    uint256 amount = emission.emitTokens();
    assertApproxEqAbs(amount, calculatedAmountFor30Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenAfter40Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor40Years = EMISSION_SUPPLY;

    vm.warp(40 * YEAR);
    uint256 amount = emission.emitTokens();
    assertEq(amount, calculatedAmountFor40Years);
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_fuzz_emitTokens_shouldNotRevert(uint256 duration) public {
    _setupEmissionContract();

    vm.assume(duration < 100 * YEAR);
    vm.assume(duration > 1 hours);

    vm.warp(duration);
    uint256 amount = emission.emitTokens();

    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), amount + INITIAL_TREASURY_BALANCE);
  }

  function test_emitTokens_whenMultipleEmits_shouldTakePreviousMintsIntoAccount() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor1Month = 3_692_586_569039559708901376;
    uint256 calculatedAmountFor1Year = 43_528_555_600215261579313152;

    vm.warp(MONTH);
    emission.emitTokens();

    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);

    vm.warp(YEAR);
    uint256 amount = emission.emitTokens();

    assertApproxEqAbs(amount, calculatedAmountFor1Year - calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);
    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor1Year, NEGLIGIBLE_AMOUNT);
  }

  function test_emitTokens_whenMultipleEmitsWithShortIntervals_shouldEmitCorrectAmounts() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor1Hour = 5_143_195032781921976320;
    uint256 calculatedAmountFor2Hours = 10_286_349369339965079552;
    uint256 calculatedAmountFor3Hours = 15_429_463010223885123584;

    vm.warp(1 hours);
    emission.emitTokens();

    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor1Hour, NEGLIGIBLE_AMOUNT);

    vm.warp(2 hours);
    uint256 amount2 = emission.emitTokens();

    assertApproxEqAbs(amount2, calculatedAmountFor2Hours - calculatedAmountFor1Hour, NEGLIGIBLE_AMOUNT);
    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor2Hours, NEGLIGIBLE_AMOUNT);

    vm.warp(3 hours);
    uint256 amount3 = emission.emitTokens();

    assertApproxEqAbs(amount3, calculatedAmountFor3Hours - calculatedAmountFor2Hours, NEGLIGIBLE_AMOUNT);
    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor3Hours, NEGLIGIBLE_AMOUNT);
  }

  function test_fuzz_emitTokens_whenMultipleEmits_shouldNotRevert(
    uint256 duration1,
    uint256 duration2,
    uint256 duration3
  ) public {
    _setupEmissionContract();

    // using duration as days to avoid "cheatcode rejected too many inputs" error
    vm.assume(duration1 < 15 * 365);
    vm.assume(duration2 < 15 * 365);
    vm.assume(duration3 < 15 * 365);

    vm.assume(duration1 > 0);
    vm.assume(duration2 > 0);
    vm.assume(duration3 > 0);

    vm.warp(duration1 * 1 days);
    uint256 amount1 = emission.emitTokens();

    vm.warp((duration1 + duration2) * 1 days);
    uint256 amount2 = emission.emitTokens();

    vm.warp((duration1 + duration2 + duration3) * 1 days);
    uint256 amount3 = emission.emitTokens();

    uint256 totalEmitted = amount1 + amount2 + amount3;

    assertEq(totalEmitted, emission.totalEmittedAmount());
    assertEq(mentoToken.balanceOf(TREASURY_CONTRACT), totalEmitted + INITIAL_TREASURY_BALANCE);
  }

  function _setupEmissionContract() internal {
    vm.startPrank(OWNER);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(TREASURY_CONTRACT);
    vm.stopPrank();
  }
}
