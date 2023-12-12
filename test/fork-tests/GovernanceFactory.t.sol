// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { BaseTest } from "../utils/BaseTest.next.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";

contract GovernanceFactoryTest is BaseTest {
  string public constant NETWORK_CELO_RPC = "celo_mainnet";
  string public constant NETWORK_ALFAJORES_RPC = "alfajores";

  function setUp() public {
    uint256 forkId = vm.createFork(NETWORK_CELO_RPC);
    vm.selectFork(forkId);
  }

  function test_createGovernance() public {
    GovernanceFactory factory = new GovernanceFactory(
      address(this),
      0x69f4D1788e39c87893C980c06EdF4b7f686e2938,
      0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC
    );
    factory.createGovernance(
      makeAddr("MentoLabsVestingMultisig"),
      makeAddr("WatchdogMultisig"),
      keccak256(abi.encodePacked("FakeRoot")),
      makeAddr("FractalSigner")
    );
  }
}
