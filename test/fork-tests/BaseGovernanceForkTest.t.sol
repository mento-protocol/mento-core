// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { MentoFork } from "./MentoFork.sol";
import { console } from "forge-std/console.sol";

/**
 * @title BaseGovernanceForkTest
 * @notice Fork tests for Mento Goverance!
 * This test suite tests invariantes on a fork of a live Mento environemnts.
 * The philosophy is to test in accordance with how the target fork is configured,
 * therfore it doesn't make assumptions about the systems, nor tries to configure
 * the system to test specific scenarios.
 * However, it should be exausitve in testing invariants across all tradable pairs
 * in the system, therfore each test should.
 */
contract BaseGovernanceForkTest is MentoFork {
  constructor(uint256 _targetChainId) public MentoFork(_targetChainId) {}

  function setUp() public {
    console.log("Goverance firing for", targetChainId);
  }
}
