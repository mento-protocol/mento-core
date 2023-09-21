// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { TestSetup } from "./TestSetup.sol";
import { MentoToken } from "contracts/governance/MentoToken.sol";

contract MentoTokenTest is TestSetup {
  /// @dev Test the state initialization post-construction of the MentoToken contract.
  function test_constructor_shouldSetCorrectState() public {
    assertEq(mentoToken.emissionContract(), address(emission));
    assertEq(mentoToken.emissionSupply(), EMISSION_SUPPLY);
    assertEq(mentoToken.emittedAmount(), 0);
  }

  /// @dev Test the correct token amounts are minted to respective contracts during initialization.
  function test_constructor_shouldMintCorrectAmounts() public {
    uint256 vestingAmount = mentoToken.balanceOf(vestingContract);
    uint256 airgrabAmount = mentoToken.balanceOf(airgrabContract);
    uint256 treasuryAmount = mentoToken.balanceOf(treasuryContract);
    uint256 emissionAmount = mentoToken.balanceOf(address(emission));

    assertEq(vestingAmount, 200_000_000 * 1e18);
    assertEq(airgrabAmount, 50_000_000 * 1e18);
    assertEq(treasuryAmount, 100_000_000 * 1e18);
    assertEq(emissionAmount, 0);

    assertEq(vestingAmount + airgrabAmount + treasuryAmount + emissionAmount, INITIAL_TOTAL_SUPPLY);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY);
  }

  /**
   * @dev Test the burn functionality for an individual account.
   * @notice Even though the burn function comes from OpenZeppelin's library,
   * @notice this test assures correct integration.
   */
  function test_burn_shouldBurnTokens() public {
    uint256 initialBalance = 3e18;
    uint256 burnAmount = 1e18;
    deal(address(mentoToken), alice, initialBalance);

    vm.startPrank(alice);
    vm.expectRevert("ERC20: burn amount exceeds balance");
    mentoToken.burn(initialBalance + 1);

    mentoToken.burn(burnAmount);
    assertEq(mentoToken.balanceOf(alice), initialBalance - burnAmount);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY - burnAmount);
  }

  /**
   * @dev Test the burnFrom functionality considering allowances.
   * @notice Even though the burnFrom function comes from OpenZeppelin's library,
   * @notice this test assures correct integration.
   */
  function test_burnFrom_whenAllowed_shouldBurnTokens() public {
    uint256 initialBalance = 3e18;
    uint256 burnAmount = 1e18;
    deal(address(mentoToken), alice, initialBalance);

    vm.prank(bob);
    vm.expectRevert("ERC20: insufficient allowance");
    mentoToken.burnFrom(alice, burnAmount);

    vm.prank(alice);
    mentoToken.approve(bob, burnAmount);

    vm.startPrank(bob);
    vm.expectRevert("ERC20: insufficient allowance");
    mentoToken.burnFrom(alice, burnAmount + 1);

    mentoToken.burnFrom(alice, burnAmount);
    assertEq(mentoToken.balanceOf(alice), initialBalance - burnAmount);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY - burnAmount);

    vm.expectRevert("ERC20: insufficient allowance");
    mentoToken.burnFrom(alice, burnAmount);
  }

  /**
   * @dev Tests the mint function's access control mechanism.
   * @dev This test ensures that the mint function can only be called by the emission contract address.
   * Any other address attempting to mint tokens should have the transaction reverted.
   */
  function test_mint_whenNotEmissionContract_shouldRevert() public {
    uint256 mintAmount = 10e18;
    vm.prank(bob);
    vm.expectRevert("MentoToken: only emission contract");
    mentoToken.mint(alice, mintAmount);
  }

  /**
   * @dev Tests the mint function's behavior when minting amounts that exceed the emission supply.
   * @notice This test ensures that when the mint function is called with an amount that
   * exceeds the total emission supply, the transaction should be reverted.
   */
  function test_mint_whenAmountBiggerThanEmissionSupply_shouldRevert() public {
    uint256 mintAmount = 10e18;

    vm.startPrank(address(emission));

    vm.expectRevert("MentoToken: emission supply exceeded");
    mentoToken.mint(alice, EMISSION_SUPPLY + 1);

    mentoToken.mint(alice, mintAmount);

    vm.expectRevert("MentoToken: emission supply exceeded");
    mentoToken.mint(alice, EMISSION_SUPPLY - mintAmount + 1);
  }

  /**
   * @dev Tests the mint function's logic for the emission contract.
   * @notice This test checks:
   * 1. Tokens can be successfully minted to specific addresses when called by the emission contract.
   * 2. The emittedAmount state variable correctly reflects the total amount of tokens emitted.
   * 3. It can mint up to emission supply
   */
  function test_mint_whenEmissionSupplyNotExceeded_shouldEmitTokens() public {
    uint256 mintAmount = 10e18;

    vm.startPrank(address(emission));
    mentoToken.mint(alice, mintAmount);

    assertEq(mentoToken.balanceOf(alice), mintAmount);
    assertEq(mentoToken.emittedAmount(), mintAmount);

    mentoToken.mint(bob, mintAmount);

    assertEq(mentoToken.balanceOf(bob), mintAmount);
    assertEq(mentoToken.emittedAmount(), 2 * mintAmount);

    mentoToken.mint(alice, EMISSION_SUPPLY - 2 * mintAmount);
    assertEq(mentoToken.emittedAmount(), EMISSION_SUPPLY);
  }
}
