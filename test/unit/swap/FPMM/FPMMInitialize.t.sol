// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable state-visibility
pragma solidity ^0.8;

import { FPMMBaseTest } from "./FPMMBaseTest.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { ERC20DecimalsMock } from "openzeppelin-contracts-next/contracts/mocks/ERC20DecimalsMock.sol";

contract FPMMInitializeTest is FPMMBaseTest {
  function test_initialize_whenDisablingInitializers_shouldRevertWhenCalledAfterConstructor() public {
    FPMM fpmmDisabled = new FPMM(true);

    vm.expectRevert("Initializable: contract is already initialized");
    fpmmDisabled.initialize(address(0), address(0), address(0), address(0), false, address(0), defaultFpmmParams);
  }

  function test_initialize_whenCalledWithCorrectParams_shouldSetProperValues()
    public
    initializeFPMM_withDecimalTokens(18, 18)
  {
    assertEq(fpmm.symbol(), "FPMM-T0/T1");
    assertEq(fpmm.name(), "Mento Fixed Price MM - T0/T1");
    assertEq(fpmm.decimals(), 18);

    assertEq(fpmm.token0(), token0);
    assertEq(fpmm.token1(), token1);
    assertEq(address(fpmm.oracleAdapter()), address(oracleAdapter));
    assertEq(fpmm.referenceRateFeedID(), referenceRateFeedID);
    assertEq(fpmm.owner(), owner);

    assertEq(fpmm.decimals0(), 1e18);
    assertEq(fpmm.decimals1(), 1e18);
  }

  function test_initialize_whenCalledTwice_shouldRevert() public initializeFPMM_withDecimalTokens(18, 18) {
    vm.expectRevert("Initializable: contract is already initialized");
    fpmm.initialize(token0, token1, address(oracleAdapter), referenceRateFeedID, false, owner, defaultFpmmParams);
  }

  function test_initialize_whenTokensHaveDifferentDecimals_shouldSetCorrectDecimalScalingFactors()
    public
    initializeFPMM_withDecimalTokens(6, 12)
  {
    assertEq(fpmm.decimals0(), 1e6);
    assertEq(fpmm.decimals1(), 1e12);
  }

  function test_initialize_whenToken0HasMoreThan18Decimals_shouldRevert() public {
    token0 = address(new ERC20DecimalsMock("token0", "T0", 19));
    token1 = address(new ERC20DecimalsMock("token1", "T1", 18));

    vm.expectRevert(IFPMM.InvalidTokenDecimals.selector);
    fpmm.initialize(token0, token1, address(oracleAdapter), referenceRateFeedID, false, owner, defaultFpmmParams);
  }

  function test_initialize_whenToken1HasMoreThan18Decimals_shouldRevert() public {
    token0 = address(new ERC20DecimalsMock("token0", "T0", 18));
    token1 = address(new ERC20DecimalsMock("token1", "T1", 19));

    vm.expectRevert(IFPMM.InvalidTokenDecimals.selector);
    fpmm.initialize(token0, token1, address(oracleAdapter), referenceRateFeedID, false, owner, defaultFpmmParams);
  }

  function test_initialize_whenBothTokensHaveMoreThan18Decimals_shouldRevert() public {
    token0 = address(new ERC20DecimalsMock("token0", "T0", 24));
    token1 = address(new ERC20DecimalsMock("token1", "T1", 20));

    vm.expectRevert(IFPMM.InvalidTokenDecimals.selector);
    fpmm.initialize(token0, token1, address(oracleAdapter), referenceRateFeedID, false, owner, defaultFpmmParams);
  }
}
