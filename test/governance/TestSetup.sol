// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Test } from "forge-std-next/Test.sol";

import { MentoToken } from "contracts/governance/MentoToken.sol";
import { Emission } from "contracts/governance/Emission.sol";

contract TestSetup is Test {
  MentoToken public mentoToken;
  Emission public emission;

  address public immutable vestingContract = makeAddr("vestingContract");
  address public immutable airgrabContract = makeAddr("airgrabContract");
  address public immutable treasuryContract = makeAddr("treasuryContract");

  address public immutable owner = makeAddr("owner");
  address public immutable alice = makeAddr("alice");
  address public immutable bob = makeAddr("bob");

  uint256 public constant INITIAL_TOTAL_SUPPLY = 350_000_000 * 1e18;
  uint256 public constant EMISSION_SUPPLY = 650_000_000 * 1e18;

  uint256 public constant MONTH = 30 days;
  uint256 public constant YEAR = 365 days;

  function setUp() public {
    vm.startPrank(owner);
    emission = new Emission();
    mentoToken = new MentoToken(vestingContract, airgrabContract, treasuryContract, address(emission));
    vm.stopPrank();
  }
}
