// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { FPMM } from "contracts/swap/FPMM.sol";

contract FPMMInitializeTest is FPMMBaseTest {
  function test_initialize_whenDisablingInitializers_shouldRevertWhenCalledAfterConstructor() public {
    FPMM fpmmDisabled = new FPMM(true);

    vm.expectRevert("Initializable: contract is already initialized");
    fpmmDisabled.initialize(address(0), address(0), address(0), address(0), address(0));
  }

  function test_initialize_whenCalledWithCorrectParams_shouldSetProperValues()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    assertEq(fpmm.symbol(), "FPMM-T0/T1");
    assertEq(fpmm.name(), "Mento Fixed Price MM - T0/T1");
    assertEq(fpmm.decimals(), 18);
    assertEq(fpmm.owner(), owner);

    assertEq(fpmm.token0(), token0);
    assertEq(fpmm.token1(), token1);
    assertEq(fpmm.decimals0(), 1e18);
    assertEq(fpmm.decimals1(), 1e18);
  }

  function test_initialize_whenCalledTwice_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.expectRevert("Initializable: contract is already initialized");
    fpmm.initialize(token0, token1, sortedOracles, breakerBox, owner);
  }

  function test_initialize_whenTokensHaveDifferentDecimals_shouldSetCorrectDecimalScalingFactors()
    public
    initializeFPMM_withDecimalTokens(6, 12)
  {
    assertEq(fpmm.decimals0(), 1e6);
    assertEq(fpmm.decimals1(), 1e12);
  }
}
