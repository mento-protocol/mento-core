// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airdrop_Test } from "./Base.t.sol";
import { Airdrop } from "contracts/governance/Airdrop.sol";

contract Constructor_Airdrop_Test is Airdrop_Test {
  uint32 public constant MAX_CLIFF_PERIOD = 103;
  uint32 public constant MAX_SLOPE_PERIOD = 104;

  function subject() internal {
    setAirdrop();
  }

  function test_Constructor() external {
    subject();

    assertEq(airdrop.root(), merkleRoot); 
    assertEq(airdrop.fractalIssuer(), fractalIssuer);
    assertEq(address(airdrop.token()), address(token));
    assertEq(address(airdrop.lockingContract()), address(lockingContract));
    assertEq(airdrop.treasury(), treasury);
    assertEq(airdrop.endTimestamp(), endTimestamp);
    assertEq(airdrop.basePercentage(), basePercentage);
    assertEq(airdrop.cliffPercentage(), cliffPercentage);
    assertEq(airdrop.requiredCliffPeriod(), requiredCliffPeriod);
    assertEq(airdrop.slopePercentage(), slopePercentage);
    assertEq(airdrop.requiredSlopePeriod(), requiredSlopePeriod);
  }

  function test_Constructor_InvalidMerkleRoot() 
    external 
  {
    merkleRoot = bytes32(0);
    vm.expectRevert("Airdrop: invalid root");
    subject();
  }

  function test_Constructor_InvalidFractalIssuer() external {
    fractalIssuer = address(0);
    vm.expectRevert("Airdrop: invalid fractal issuer");
    subject();
  }

  function test_Constructor_InvalidToken() external {
    tokenAddress = address(0);
    vm.expectRevert("Airdrop: invalid token");
    subject();
  }

  function test_Constructor_InvalidTreasury() external {
    treasury = payable(address(0));
    vm.expectRevert("Airdrop: invalid treasury");
    subject();
  }

  function test_Constructor_InvalidEndTimestamp() external {
    endTimestamp = block.timestamp;
    vm.expectRevert("Airdrop: invalid end timestamp");
    subject();
  }

  function test_Constructor_InvalidTotalPercentage() external {
    basePercentage = 0;
    vm.expectRevert("Airdrop: unlock percentages must add up to 1");
    subject();
  }

  function test_Constructor_InvalidCliffPeriod() external {
    requiredCliffPeriod = MAX_CLIFF_PERIOD + 1;
    vm.expectRevert("Airdrop: required cliff period too large");
    subject();
  }

  function test_Constructor_InvalidSlopePeriod() external {
    requiredSlopePeriod = MAX_SLOPE_PERIOD + 1;
    vm.expectRevert("Airdrop: required slope period too large");
    subject();
  }
}
