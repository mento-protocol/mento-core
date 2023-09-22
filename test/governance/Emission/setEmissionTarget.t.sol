// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
import { Emission_Test } from "./Base.t.sol";

contract SetEmissionTarget_Emission_Test is Emission_Test {
  address public newEmissionTarget = makeAddr("NewEmissionTarget");

  function setUp() public {
    _newEmission();
  }

  function _subject() internal {
    emission.setEmissionTarget(newEmissionTarget);
  }

  function test_setEmissionTarget_shouldRevert_whenNoOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    _subject();
  }

  function test_setEmissionTarget_shouldSetEmissionTarget_whenOwner() public {
    vm.prank(owner);
    vm.expectEmit(true, true, true, true);
    emit EmissionTargetSet(newEmissionTarget);
    _subject();

    assertEq(address(emission.emissionTarget()), newEmissionTarget);
  }
}
