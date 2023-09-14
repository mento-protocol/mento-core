// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Test } from "forge-std-next/Test.sol";

import { MentoToken } from "contracts/governance/MentoToken.sol";
import { Emission } from "contracts/governance/Emission.sol";

contract TestSetup is Test {
  MentoToken public mentoToken;
  Emission public emission;

  address public constant VESTING_CONTRACT = address(111);
  address public constant AIRGRAB_CONTRACT = address(222);
  address public constant TREASURY_CONTRACT = address(333);

  address public constant OWNER = address(1111);
  address public constant ALICE = address(9999);
  address public constant BOB = address(8888);

  uint256 public constant INITIAL_TOTAL_SUPPLY = 350_000_000 * 1e18;
  uint256 public constant EMISSION_SUPPLY = 650_000_000 * 1e18;

  uint256 public constant MONTH = 30 days;
  uint256 public constant YEAR = 365 days;

  function setUp() public {
    vm.startPrank(OWNER);
    emission = new Emission();
    mentoToken = new MentoToken(VESTING_CONTRACT, AIRGRAB_CONTRACT, TREASURY_CONTRACT, address(emission));
    vm.stopPrank();
  }
}
