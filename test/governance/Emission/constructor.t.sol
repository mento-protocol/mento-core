// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, contract-name-camelcase

import { Emission_Test } from "./Base.t.sol";

contract Constructor_Emission_Test is Emission_Test {
  function _subject() internal {
    _newEmission();
  }

  function test_constructor_shouldSetOwner() public {
    _subject();
    assertEq(emission.owner(), owner);
  }
}
