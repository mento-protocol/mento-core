// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { console } from "forge-std-next/console.sol";
import { Test } from "forge-std-next/Test.sol";

import { MentoToken } from "contracts/governance/MentoToken.sol";

contract MentoTokenTest is Test {
  MentoToken public mentoToken;

  address public constant VESTING_CONTRACT = address(111);
  address public constant AIRGRAB_CONTRACT = address(222);
  address public constant TREASURY_CONTRACT = address(333);
  address public constant EMISSION_CONTRACT = address(444);

  address public constant ALICE = address(9999);
  address public constant BOB = address(8888);

  uint256 public constant INITIAL_TOTAL_SUPPLY = 350_000_000 * 1e18;
  uint256 public constant EMISSION_SUPPLY = 650_000_000 * 1e18;

  function setUp() public {
    mentoToken = new MentoToken(VESTING_CONTRACT, AIRGRAB_CONTRACT, TREASURY_CONTRACT, EMISSION_CONTRACT);
  }

  /// @dev Test the state initialization post-construction of the MentoToken contract.
  function test_constructor_shouldSetCorrectState() public {
    assertEq(mentoToken.emissionContract(), EMISSION_CONTRACT);
    assertEq(mentoToken.emissionSupply(), EMISSION_SUPPLY);
    assertEq(mentoToken.emittedAmount(), 0);
  }

  /// @dev Test the correct token amounts are minted to respective contracts during initialization.
  function test_constructor_shouldMintCorrectAmounts() public {
    // Fetch the balances of all the addresses set during contract initialization
    uint256 vestingAmount = mentoToken.balanceOf(VESTING_CONTRACT);
    uint256 airgrabAmount = mentoToken.balanceOf(AIRGRAB_CONTRACT);
    uint256 treasuryAmount = mentoToken.balanceOf(TREASURY_CONTRACT);
    uint256 emissionAmount = mentoToken.balanceOf(EMISSION_CONTRACT);

    // Assert that each contract has the expected amount of tokens
    assertEq(vestingAmount, 200_000_000 * 1e18);
    assertEq(airgrabAmount, 50_000_000 * 1e18);
    assertEq(treasuryAmount, 100_000_000 * 1e18);
    assertEq(emissionAmount, 0);

    // Assert that the total token minted during initialization matches the sum of tokens assigned to each contract
    assertEq(vestingAmount + airgrabAmount + treasuryAmount + emissionAmount, INITIAL_TOTAL_SUPPLY);
    // Assert that the token's total supply matches the predefined initial total supply
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY);
  }

  /**
   * @dev Test the burn functionality for an individual account.
   * @notice Even though the burn function comes from OpenZeppelin's library,
   * @notice this test assures correct integration.
   */
  function test_burn_shouldBurnTokens() public {
    // Set up initial parameters and balances
    uint256 initialBalance = 3e18;
    uint256 burnAmount = 1e18;
    deal(address(mentoToken), ALICE, initialBalance);

    // Expect a revert since ALICE is trying to burn more tokens than their balance
    vm.startPrank(ALICE);
    vm.expectRevert("ERC20: burn amount exceeds balance");
    mentoToken.burn(initialBalance + 1);

    // Successfully burn tokens and assert the results
    mentoToken.burn(burnAmount);
    assertEq(mentoToken.balanceOf(ALICE), initialBalance - burnAmount);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY - burnAmount);
  }

  /**
   * @dev Test the burnFrom functionality considering allowances.
   * @notice Even though the burnFrom function comes from OpenZeppelin's library,
   * @notice this test assures correct integration.
   */
  function test_burnFrom_shouldBurnTokens_upToAllowance() public {
    // Set up initial parameters and balances
    uint256 initialBalance = 3e18;
    uint256 burnAmount = 1e18;
    deal(address(mentoToken), ALICE, initialBalance);

    // BOB tries to burn ALICE's tokens without any allowance. This should fail.
    vm.prank(BOB);
    vm.expectRevert("ERC20: insufficient allowance");
    mentoToken.burnFrom(ALICE, burnAmount);

    // ALICE approves BOB for a specific amount of their tokens
    vm.prank(ALICE);
    mentoToken.approve(BOB, burnAmount);

    // BOB tries to burn more tokens than the allowance. This should fail.
    vm.startPrank(BOB);
    vm.expectRevert("ERC20: insufficient allowance");
    mentoToken.burnFrom(ALICE, burnAmount + 1);

    // BOB successfully burns up to the allowed amount of ALICE's tokens and asserts the results
    mentoToken.burnFrom(ALICE, burnAmount);
    assertEq(mentoToken.balanceOf(ALICE), initialBalance - burnAmount);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY - burnAmount);

    // BOB tries to burn again, but the allowance is now exhausted. This should fail.
    vm.expectRevert("ERC20: insufficient allowance");
    mentoToken.burnFrom(ALICE, burnAmount);
  }

  /**
   * @dev Tests the mint function's access control mechanism.
   * @dev This test ensures that the mint function can only be called by the emission contract address.
   * Any other address attempting to mint tokens should have the transaction reverted.
   */
  function test_mint_shouldRevert_forUnauthorizedAccounts() public {
    uint256 mintAmount = 10e18;
    vm.prank(BOB);
    vm.expectRevert("MentoToken: OnlyEmissionContract");
    mentoToken.mint(ALICE, mintAmount);
  }

  /**
   * @dev Tests the mint function's behavior when minting amounts that exceed the emission supply.
   * @notice This test ensures that when the mint function is called with an amount that
   * exceeds the total emission supply, the transaction should be reverted.
   */
  function test_mint_shouldRevert_forAmountsBiggerThanSupply() public {
    uint256 mintAmount = 10e18;

    vm.startPrank(EMISSION_CONTRACT);

    vm.expectRevert("MentoToken: EmissionSupplyExceeded");
    mentoToken.mint(ALICE, EMISSION_SUPPLY + 1);

    mentoToken.mint(ALICE, mintAmount);

    vm.expectRevert("MentoToken: EmissionSupplyExceeded");
    mentoToken.mint(ALICE, EMISSION_SUPPLY - mintAmount + 1);
  }

  /**
   * @dev Tests the mint function's logic for the emission contract.
   * @notice This test checks:
   * 1. Tokens can be successfully minted to specific addresses when called by the emission contract.
   * 2. The emittedAmount state variable correctly reflects the total amount of tokens emitted.
   * 3. It can mint up to emission supply
   */
  function test_mint_shouldEmitTokens_forEmissionContract_upToEmissionSupply() public {
    uint256 mintAmount = 10e18;

    vm.startPrank(EMISSION_CONTRACT);
    mentoToken.mint(ALICE, mintAmount);

    assertEq(mentoToken.balanceOf(ALICE), mintAmount);
    assertEq(mentoToken.emittedAmount(), mintAmount);

    mentoToken.mint(BOB, mintAmount);

    assertEq(mentoToken.balanceOf(BOB), mintAmount);
    assertEq(mentoToken.emittedAmount(), 2 * mintAmount);

    mentoToken.mint(ALICE, EMISSION_SUPPLY - 2 * mintAmount);
    assertEq(mentoToken.emittedAmount(), EMISSION_SUPPLY);
  }
}
