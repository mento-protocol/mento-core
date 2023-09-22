// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
import { Emission_Test } from "./Base.t.sol";

contract TransferOwnership_Emission_Test is Emission_Test {
  function setUp() public {
    _newEmission();
  }

  function _subject() internal {
    emission.transferOwnership(alice);
  }

  function test_transferOwnership_shouldRevert_whenNoOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    _subject();
  }

  function test_transferOwnership_whenOwner_shouldSetNewOwner() public {
    vm.prank(owner);
    _subject();

    assertEq(emission.owner(), alice);
  }
}
