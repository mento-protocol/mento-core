// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Emission_Test } from "./Base.t.sol";

contract RenounceOwnership_Emission_Test is Emission_Test {
  function setUp() public {
    _newEmission();
  }

  function _subject() internal {
    emission.renounceOwnership();
  }

  function test_renounceOwnership_shouldRevert_whenNoOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    _subject();
  }

  function test_renounceOwnership_shouldRemoveOwner_whenOwner() public {
    vm.prank(owner);
    _subject();

    assertEq(emission.owner(), address(0));
  }
}
