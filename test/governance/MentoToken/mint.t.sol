// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MentoToken_Test } from "./Base.t.sol";

/**
 * @notice Even though the burn function comes from OpenZeppelin's library,
 * @notice this test assures correct integration.
 */
contract Mint_MentoToken_Test is MentoToken_Test {
  uint256 mintAmount;
  address target;

  function setUp() public {
    _newMentoToken();
    target = alice;
  }

  function _subject() internal {
    mentoToken.mint(target, mintAmount);
  }

  function test_mint_whenNotEmissionContract_shouldRevert() public {
    mintAmount = 10e18;

    vm.expectRevert("MentoToken: only emission contract");
    _subject();
  }

  function test_mint_shouldRevert_whenAmountBiggerThanEmissionSupply() public {
    mintAmount = EMISSION_SUPPLY + 1;

    vm.prank(emissionContract);
    vm.expectRevert("MentoToken: emission supply exceeded");
    _subject();
  }

  function test_mint_shouldRevert_whenAmountBiggerThanEmissionSupply_inMultiStep() public {
    mintAmount = 10e18;

    vm.prank(emissionContract);
    _subject();

    mintAmount = EMISSION_SUPPLY - mintAmount + 1;
    vm.prank(emissionContract);
    vm.expectRevert("MentoToken: emission supply exceeded");
    _subject();
  }

  function test_mint_shouldEmitTokens() public {
    mintAmount = 10e18;

    vm.prank(emissionContract);
    _subject();

    assertEq(mentoToken.balanceOf(alice), mintAmount);
    assertEq(mentoToken.emittedAmount(), mintAmount);

    target = bob;

    vm.prank(emissionContract);
    _subject();

    assertEq(mentoToken.balanceOf(bob), mintAmount);
    assertEq(mentoToken.emittedAmount(), 2 * mintAmount);
  }
}
