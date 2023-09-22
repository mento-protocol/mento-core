// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { MentoToken_Test } from "./Base.t.sol";

contract Constructor_MentoToken_Test is MentoToken_Test {
  function _subject() internal {
    _newMentoToken();
  }

  /// @dev Test the state initialization post-construction of the MentoToken contract.
  function test_constructor_shouldSetCorrectState() external {
    _subject();

    assertEq(mentoToken.name(), "Mento Token");
    assertEq(mentoToken.symbol(), "MENTO");
    assertEq(mentoToken.emissionContract(), emissionContract);
    assertEq(mentoToken.emissionSupply(), EMISSION_SUPPLY);
    assertEq(mentoToken.emittedAmount(), 0);
  }

  /// @dev Test the correct token amounts are minted to respective contracts during initialization.
  function test_constructor_shouldMintCorrectAmounts() external {
    _subject();

    uint256 vestingAmount = mentoToken.balanceOf(vestingContract);
    uint256 airgrabAmount = mentoToken.balanceOf(airgrabContract);
    uint256 treasuryAmount = mentoToken.balanceOf(treasuryContract);
    uint256 emissionAmount = mentoToken.balanceOf(emissionContract);

    assertEq(vestingAmount, 200_000_000 * 1e18);
    assertEq(airgrabAmount, 50_000_000 * 1e18);
    assertEq(treasuryAmount, 100_000_000 * 1e18);
    assertEq(emissionAmount, 0);

    assertEq(vestingAmount + airgrabAmount + treasuryAmount + emissionAmount, INITIAL_TOTAL_SUPPLY);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY);
  }
}
