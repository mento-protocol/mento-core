// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airgrab_Test } from "./Base.t.sol";
import { Airgrab } from "contracts/governance/Airgrab.sol";

contract Constructor_Airgrab_Test is Airgrab_Test {
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /// @notice Subject of the test: Airgrab constructor
  function subject() internal {
    newAirgrab();
  }

  /// @notice Check that all parameters are set correctly during initialization
  /// and that ownership is transferred to the caller.
  function test_Constructor() external {
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(address(0), address(this));
    subject();

    assertEq(airgrab.root(), merkleRoot);
    assertEq(airgrab.fractalIssuer(), fractalIssuer);
    assertEq(address(airgrab.token()), address(0));
    assertEq(address(airgrab.owner()), address(this));
    assertEq(address(airgrab.lockingContract()), address(lockingContract));
    assertEq(airgrab.treasury(), treasury);
    assertEq(airgrab.endTimestamp(), endTimestamp);
    assertEq(airgrab.basePercentage(), basePercentage);
    assertEq(airgrab.cliffPercentage(), cliffPercentage);
    assertEq(airgrab.requiredCliffPeriod(), requiredCliffPeriod);
    assertEq(airgrab.slopePercentage(), slopePercentage);
    assertEq(airgrab.requiredSlopePeriod(), requiredSlopePeriod);
  }

  /// @notice Checks the merke root
  function test_Constructor_InvalidMerkleRoot() external {
    merkleRoot = bytes32(0);
    vm.expectRevert("Airgrab: invalid root");
    subject();
  }

  /// @notice Checks the fractal issuer address
  function test_Constructor_InvalidFractalIssuer() external {
    fractalIssuer = address(0);
    vm.expectRevert("Airgrab: invalid fractal issuer");
    subject();
  }

  /// @notice Checks th treasury address
  function test_Constructor_InvalidTreasury() external {
    treasury = payable(address(0));
    vm.expectRevert("Airgrab: invalid treasury");
    subject();
  }

  /// @notice Checks the airgrab end time
  function test_Constructor_InvalidEndTimestamp() external {
    endTimestamp = block.timestamp;
    vm.expectRevert("Airgrab: invalid end timestamp");
    subject();
  }

  /// @notice Ensures base + cliff + slope percentages add up to 1
  function test_Constructor_InvalidTotalPercentage() external {
    basePercentage = 0;
    vm.expectRevert("Airgrab: unlock percentages must add up to 1");
    subject();
  }

  /// @notice Checks the cliff period based on MAX_CLIF_PERIOD
  function test_Constructor_InvalidCliffPeriod() external {
    requiredCliffPeriod = MAX_CLIFF_PERIOD + 1;
    vm.expectRevert("Airgrab: required cliff period too large");
    subject();
  }

  /// @notice Checks the slope period based on MAX_SLOPE_PERIOD
  function test_Constructor_InvalidSlopePeriod() external {
    requiredSlopePeriod = MAX_SLOPE_PERIOD + 1;
    vm.expectRevert("Airgrab: required slope period too large");
    subject();
  }
}
