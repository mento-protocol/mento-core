// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { MentoToken_Test } from "./Base.t.sol";

/**
 * @notice Even though the burn function comes from OpenZeppelin's library,
 * @notice this test assures correct integration.
 */
contract Burn_MentoToken_Test is MentoToken_Test {
  uint256 public initialBalance = 3e18;
  uint256 public burnAmount;

  function setUp() public {
    _newMentoToken();

    deal(address(mentoToken), alice, initialBalance);
  }

  function _subject() internal {
    mentoToken.burn(burnAmount);
  }

  function test_burn_shouldRevert_whenExceedsBalance() public {
    burnAmount = initialBalance + 1;

    vm.prank(alice);
    vm.expectRevert("ERC20: burn amount exceeds balance");
    _subject();
  }

  function test_burn_shouldBurn() public {
    burnAmount = 1e18;

    vm.prank(alice);
    _subject();

    assertEq(mentoToken.balanceOf(alice), initialBalance - burnAmount);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY - burnAmount);
  }
}
