// solhint-disable func-name-mixedcase
// solhint-disable max-line-length
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Test } from "forge-std-next/Test.sol";

contract TestSetup is Test {
  address public immutable owner = makeAddr("owner");
  address public immutable alice = makeAddr("alice");
  address public immutable bob = makeAddr("bob");
  address public immutable charlie = makeAddr("charlie");

  uint256 public constant INITIAL_TOTAL_SUPPLY = 350_000_000 * 1e18;
  uint256 public constant EMISSION_SUPPLY = 650_000_000 * 1e18;

  uint256 public constant MONTH = 30 days;
  uint256 public constant YEAR = 365 days;

  uint256 public constant BLOCKS_DAY = 17_280; // in CELO
  uint256 public constant BLOCKS_WEEK = 120_960; // in CELO
}
