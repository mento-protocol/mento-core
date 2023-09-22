// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Emission_Test } from "./Base.t.sol";

contract SetTokenContract_Emission_Test is Emission_Test {
  address newTokenContract = makeAddr("NewTokenContract");

  function setUp() public {
    _newEmission();
  }

  function _subject() internal {
    emission.setTokenContract(newTokenContract);
  }

  function test_setToken_shouldRevert_whenNoOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    _subject();
  }

  function test_setToken_shouldSetTokenAddress_whenOwner() public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true);
    emit TokenContractSet(newTokenContract);
    _subject();

    assertEq(address(emission.mentoToken()), newTokenContract);
  }
}
