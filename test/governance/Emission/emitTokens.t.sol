// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Emission_Test } from "./Base.t.sol";

contract EmitTokens_Emission_Test is Emission_Test {
  uint256 public constant INITIAL_TREASURY_BALANCE = 100_000_000 * 1e18;
  uint256 public constant NEGLIGIBLE_AMOUNT = 2e18;

  function setUp() public {
    _newEmission();
    _setupEmissionContract();
  }

  function _subject() internal returns (uint256) {
    return emission.emitTokens();
  }

  function test_emitTokens_whenAfter1Month_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor1Month = 3_692_586_569039559708901376;

    vm.warp(MONTH);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenAfter6Months_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor6Months = 21_843_234_315804553582215168;

    vm.warp(6 * MONTH);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor6Months, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenAfter1Year_shouldMintCorrectAmountToTarget() public {
    uint256 calculatedAmountFor1Year = 43_528_555_600215261579313152;

    vm.warp(YEAR);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor1Year, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenAfter10Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor10Years = 325_091_005_832242294004121600;

    vm.warp(10 * YEAR);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor10Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenAfter15Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor15Years = 421_181_077_873262995273940992;

    vm.warp(15 * YEAR);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor15Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenAfter25Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor25Years = 554_584_121_845194220594266112;

    vm.warp(25 * YEAR);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor25Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenAfter30Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor30Years = 624_618_096_854971046875365376;

    vm.warp(30 * YEAR);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor30Years, NEGLIGIBLE_AMOUNT);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenAfter40Years_shouldMintCorrectAmountToTarget() public {
    _setupEmissionContract();
    uint256 calculatedAmountFor40Years = EMISSION_SUPPLY;

    vm.warp(40 * YEAR);
    uint256 amount = _subject();

    assertEq(amount, calculatedAmountFor40Years);
    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_emitTokens_whenMultipleEmits_shouldTakePreviousMintsIntoAccount() public {
    uint256 calculatedAmountFor1Month = 3_692_586_569039559708901376;
    uint256 calculatedAmountFor1Year = 43_528_555_600215261579313152;

    vm.warp(MONTH);
    _subject();

    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);

    vm.warp(YEAR);
    uint256 amount = _subject();

    assertApproxEqAbs(amount, calculatedAmountFor1Year - calculatedAmountFor1Month, NEGLIGIBLE_AMOUNT);
    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor1Year, NEGLIGIBLE_AMOUNT);
  }

  function test_emitTokens_whenMultipleEmitsWithShortIntervals_shouldEmitCorrectAmounts() public {
    uint256 calculatedAmountFor1Hour = 5_143_195032781921976320;
    uint256 calculatedAmountFor2Hours = 10_286_349369339965079552;
    uint256 calculatedAmountFor3Hours = 15_429_463010223885123584;

    vm.warp(1 hours);
    _subject();

    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor1Hour, NEGLIGIBLE_AMOUNT);

    vm.warp(2 hours);
    uint256 amount2 = _subject();

    assertApproxEqAbs(amount2, calculatedAmountFor2Hours - calculatedAmountFor1Hour, NEGLIGIBLE_AMOUNT);
    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor2Hours, NEGLIGIBLE_AMOUNT);

    vm.warp(3 hours);
    uint256 amount3 = emission.emitTokens();

    assertApproxEqAbs(amount3, calculatedAmountFor3Hours - calculatedAmountFor2Hours, NEGLIGIBLE_AMOUNT);
    assertApproxEqAbs(emission.totalEmittedAmount(), calculatedAmountFor3Hours, NEGLIGIBLE_AMOUNT);
  }

  function test_fuzz_emitTokens_shouldNotRevert(uint256 duration) public {
    vm.assume(duration < 100 * YEAR);
    vm.assume(duration > 1 hours);

    vm.warp(duration);
    uint256 amount = _subject();

    assertEq(mentoToken.balanceOf(emissionTarget), amount);
  }

  function test_fuzz_emitTokens_whenMultipleEmits_shouldNotRevert(
    uint256 duration1,
    uint256 duration2,
    uint256 duration3
  ) public {
    // using duration as days to avoid "cheatcode rejected too many inputs" error
    vm.assume(duration1 < 15 * 365);
    vm.assume(duration2 < 15 * 365);
    vm.assume(duration3 < 15 * 365);

    vm.assume(duration1 > 0);
    vm.assume(duration2 > 0);
    vm.assume(duration3 > 0);

    vm.warp(duration1 * 1 days);
    uint256 amount1 = _subject();

    vm.warp((duration1 + duration2) * 1 days);
    uint256 amount2 = _subject();

    vm.warp((duration1 + duration2 + duration3) * 1 days);
    uint256 amount3 = _subject();

    uint256 totalEmitted = amount1 + amount2 + amount3;

    assertEq(totalEmitted, emission.totalEmittedAmount());
    assertEq(mentoToken.balanceOf(emissionTarget), totalEmitted);
  }
}
