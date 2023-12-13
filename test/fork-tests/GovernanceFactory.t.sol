// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { BaseTest } from "../utils/BaseTest.next.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";

contract GovernanceFactoryForkTest is BaseTest {
  string public constant NETWORK_CELO_RPC = "celo_mainnet";
  string public constant NETWORK_ALFAJORES_RPC = "alfajores";

  function setUp() public {
    uint256 forkId = vm.createFork(NETWORK_CELO_RPC);
    vm.selectFork(forkId);
  }

  function test_createGovernance() public {
    GovernanceFactory factory = new GovernanceFactory(address(this));
    factory.createGovernance(
      makeAddr("MentoLabsMultiSig"),
      makeAddr("WatchdogMultiSig"),
      makeAddr("CommunityFund"),
      keccak256(abi.encodePacked("FakeRoot")),
      makeAddr("FractalSigner")
    );
  }
}
