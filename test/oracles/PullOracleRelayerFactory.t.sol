// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, private-vars-leading-underscore
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase, one-contract-per-file
pragma solidity ^0.8.19;

import { Test } from "mento-std/Test.sol";

import { MockVerifierProxy } from "test/utils/mocks/MockVerifierProxy.sol";
import { IPullOracleRelayerFactory } from "contracts/interfaces/IPullOracleRelayerFactory.sol";
import { IPullOracleRelayer } from "contracts/interfaces/IPullOracleRelayer.sol";
import { PullOracleRelayerFactory } from "contracts/oracles/PullOracleRelayerFactory.sol";
import { ChainlinkDataStreamsAdapter } from "contracts/oracles/adapters/ChainlinkDataStreamsAdapter.sol";

interface ISortedOracles {
  function initialize(uint256) external;

  function addOracle(address, address) external;

  function setTokenReportExpiry(address, uint256) external;

  function medianRate(address) external returns (uint256, uint256);
}

contract PullOracleRelayerFactoryTest is Test {
  IPullOracleRelayerFactory factory;
  ISortedOracles sortedOracles;
  MockVerifierProxy verifierProxy;
  ChainlinkDataStreamsAdapter adapter;

  address owner = makeAddr("owner");
  address relayerDeployer = makeAddr("relayerDeployer");
  address nonDeployer = makeAddr("nonDeployer");

  address aRateFeed = makeAddr("CELO/PHP");
  string aDescription = "CELO/PHP";
  uint256 maxStaleness = 600;

  bytes32 feedId0 = 0x0003000000000000000000000000000000000000000000000000000000000001; // CELO/USD (V3)
  bytes32 feedId1 = 0x0003000000000000000000000000000000000000000000000000000000000002; // PHP/USD (V3)

  bytes constant NOT_ALLOWED_ERROR = abi.encodeWithSignature("NotAllowed()");

  function setUp() public virtual {
    vm.warp(100_000);
    sortedOracles = ISortedOracles(deployCode("SortedOracles", abi.encode(true)));
    sortedOracles.initialize(3600);
    verifierProxy = new MockVerifierProxy();
    adapter = new ChainlinkDataStreamsAdapter(address(verifierProxy));

    factory = IPullOracleRelayerFactory(new PullOracleRelayerFactory(false));
    vm.prank(owner);
    factory.initialize(address(sortedOracles), address(adapter), relayerDeployer);
  }

  function oneLeg() internal view returns (IPullOracleRelayer.OracleLeg[] memory legs) {
    legs = new IPullOracleRelayer.OracleLeg[](1);
    legs[0] = IPullOracleRelayer.OracleLeg(feedId0, false);
  }

  function twoLegs() internal view returns (IPullOracleRelayer.OracleLeg[] memory legs) {
    legs = new IPullOracleRelayer.OracleLeg[](2);
    legs[0] = IPullOracleRelayer.OracleLeg(feedId0, false);
    legs[1] = IPullOracleRelayer.OracleLeg(feedId1, true);
  }

  function deployOneLeg() internal returns (address) {
    vm.prank(relayerDeployer);
    return factory.deployRelayer(aRateFeed, aDescription, 0, maxStaleness, oneLeg());
  }

  function buildReport(bytes32 feedId, int192 price) internal view returns (bytes memory) {
    return
      abi.encode(
        feedId,
        uint32(0),
        uint32(block.timestamp),
        uint192(0),
        uint192(0),
        uint32(block.timestamp + 1000),
        price,
        int192(0),
        int192(0)
      );
  }

  function wrap(bytes memory a) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](1);
    arr[0] = a;
  }
}

contract PullOracleRelayerFactoryTest_initialize is PullOracleRelayerFactoryTest {
  function test_setsConfig() public view {
    assertEq(factory.sortedOracles(), address(sortedOracles));
    assertEq(factory.adapter(), address(adapter));
    assertEq(factory.relayerDeployer(), relayerDeployer);
  }
}

contract PullOracleRelayerFactoryTest_deploy is PullOracleRelayerFactoryTest {
  function test_deploy_onlyDeployer() public {
    vm.prank(nonDeployer);
    vm.expectRevert(NOT_ALLOWED_ERROR);
    factory.deployRelayer(aRateFeed, aDescription, 0, maxStaleness, oneLeg());
  }

  function test_deploy_matchesComputedCreate2Address() public {
    address expected = factory.computeRelayerAddress(aRateFeed, aDescription, 0, maxStaleness, oneLeg());
    address deployed = deployOneLeg();
    assertEq(deployed, expected);
    assertEq(factory.getRelayer(aRateFeed), deployed);
  }

  function test_deploy_forwardsConfigToRelayer() public {
    address deployed = deployOneLeg();
    IPullOracleRelayer relayer = IPullOracleRelayer(deployed);
    assertEq(relayer.sortedOracles(), address(sortedOracles));
    assertEq(relayer.adapter(), address(adapter));
    assertEq(relayer.maxStaleness(), maxStaleness);
    assertEq(relayer.rateFeedId(), aRateFeed);
  }

  function test_deploy_revertsOnDuplicate() public {
    deployOneLeg();
    vm.prank(relayerDeployer);
    vm.expectRevert(abi.encodeWithSignature("RelayerForFeedExists(address)", aRateFeed));
    factory.deployRelayer(aRateFeed, aDescription, 0, maxStaleness, oneLeg());
  }

  function test_deploy_enumerates() public {
    deployOneLeg();
    address[] memory relayers = factory.getRelayers();
    assertEq(relayers.length, 1);
    assertEq(relayers[0], factory.getRelayer(aRateFeed));
  }

  function test_salt_isConstant() public {
    // Two different factories must compute different addresses (address(this) is in the salt preimage),
    // but the same factory must be deterministic across calls.
    address a = factory.computeRelayerAddress(aRateFeed, aDescription, 0, maxStaleness, oneLeg());
    address b = factory.computeRelayerAddress(aRateFeed, aDescription, 0, maxStaleness, oneLeg());
    assertEq(a, b);
  }
}

contract PullOracleRelayerFactoryTest_removeRedeploy is PullOracleRelayerFactoryTest {
  function test_remove() public {
    deployOneLeg();
    vm.prank(relayerDeployer);
    factory.removeRelayer(aRateFeed);
    assertEq(factory.getRelayer(aRateFeed), address(0));
    assertEq(factory.getRelayers().length, 0);
  }

  function test_remove_revertsWhenNone() public {
    vm.prank(relayerDeployer);
    vm.expectRevert(abi.encodeWithSignature("NoRelayerForRateFeedId(address)", aRateFeed));
    factory.removeRelayer(aRateFeed);
  }

  function test_redeploy_swapsLegs() public {
    address first = deployOneLeg();
    vm.prank(relayerDeployer);
    address second = factory.redeployRelayer(aRateFeed, aDescription, 300, maxStaleness, twoLegs());
    // Same salt + same constructor args except legs/spread ⇒ different init code ⇒ different address.
    assertTrue(first != second);
    assertEq(factory.getRelayer(aRateFeed), second);
    assertEq(IPullOracleRelayer(second).getLegs().length, 2);
  }
}

contract PullOracleRelayerFactoryTest_ingest is PullOracleRelayerFactoryTest {
  function test_ingest_routesToRelayerAndWrites() public {
    address relayer = deployOneLeg();
    sortedOracles.addOracle(aRateFeed, relayer);

    int192 price = 5e17;
    vm.prank(makeAddr("anyone"));
    factory.ingest(aRateFeed, abi.encode(wrap(buildReport(feedId0, price))));

    (uint256 median, ) = sortedOracles.medianRate(aRateFeed);
    assertEq(median, uint256(uint192(price)) * 1e6);
    assertEq(IPullOracleRelayer(relayer).lastObservationsTimestamp(), block.timestamp);
  }

  function test_ingest_revertsWhenNoRelayer() public {
    vm.expectRevert(abi.encodeWithSignature("NoRelayerForRateFeedId(address)", aRateFeed));
    factory.ingest(aRateFeed, abi.encode(wrap(buildReport(feedId0, 5e17))));
  }
}
