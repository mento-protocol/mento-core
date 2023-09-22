// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { MentoToken_Test } from "./Base.t.sol";

/**
 * @notice Even though the burn function comes from OpenZeppelin's library,
 * @notice this test assures correct integration.
 */
contract BurnFrom_MentoToken_Test is MentoToken_Test {
  uint256 initialBalance = 3e18;
  uint256 burnAmount = 1e18;

  function setUp() public {
    _newMentoToken();

    deal(address(mentoToken), alice, initialBalance);
  }

  function _subject() internal {
    mentoToken.burnFrom(alice, burnAmount);
  }

  function test_burnFrom_shouldRevert_whenNotAllowed() public {
    vm.prank(bob);
    vm.expectRevert("ERC20: insufficient allowance");
    _subject();
  }

  function test_burnFrom_shouldBurnTokens_whenAllowed() public {
    vm.prank(alice);
    mentoToken.approve(bob, burnAmount);

    vm.prank(bob);
    _subject();

    assertEq(mentoToken.balanceOf(alice), initialBalance - burnAmount);
    assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY - burnAmount);
  }

  function test_burnFrom_shouldRevert_whenAllowenceUsed() public {
    vm.prank(alice);
    mentoToken.approve(bob, burnAmount);

    vm.prank(bob);
    _subject();

    vm.prank(bob);
    vm.expectRevert("ERC20: insufficient allowance");
    _subject();
  }
}
