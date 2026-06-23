// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script, console } from "forge-std/Script.sol";

import { MockVerifierProxy } from "test/utils/mocks/MockVerifierProxy.sol";
import { DataStreamsRelayerFactory } from "contracts/oracles/DataStreamsRelayerFactory.sol";
import { DataStreamsRelayerFactoryProxy } from "contracts/oracles/DataStreamsRelayerFactoryProxy.sol";
import { DataStreamsRelayerFactoryProxyAdmin } from "contracts/oracles/DataStreamsRelayerFactoryProxyAdmin.sol";
import { IDataStreamsRelayer } from "contracts/interfaces/IDataStreamsRelayer.sol";
import { IDataStreamsRelayerFactory } from "contracts/interfaces/IDataStreamsRelayerFactory.sol";

/**
 * @title DeployDataStreamsForkHarness
 * @notice LOCAL FORK ONLY. Deploys a Data Streams stack against a forked Celo mainnet using a
 *         MockVerifierProxy in place of the real Chainlink VerifierProxy, so signed reports can be
 *         synthesized locally (we cannot mint real DON signatures pre-B1/B4). It deploys the
 *         factory (pointed at the mock verifier + the real SortedOracles) and one single-leg
 *         relayer for a real rate feed. RouterWithReports (Solidity 0.8.24) is deployed separately
 *         via `forge create`, and the relayer is authorized on SortedOracles via `cast` — both
 *         orchestrated by script/fork-harness.sh.
 *
 * Env:
 *   HARNESS_SORTED_ORACLES   real Celo SortedOracles
 *   HARNESS_RATE_FEED        the pool's referenceRateFeedID to report for
 *   (RouterWithReports / addOracle handled by the shell wrapper)
 */
contract DeployDataStreamsForkHarness is Script {
  function run() public {
    address sortedOracles = vm.envAddress("HARNESS_SORTED_ORACLES");
    address rateFeedId = vm.envAddress("HARNESS_RATE_FEED");
    address deployer = msg.sender;

    vm.startBroadcast(deployer);

    // Mock verifier: echoes the payload as the verified report (no real signature needed).
    MockVerifierProxy verifier = new MockVerifierProxy();

    // Factory behind a transparent proxy, pointed at the mock verifier + real SortedOracles.
    DataStreamsRelayerFactory impl = new DataStreamsRelayerFactory(true);
    DataStreamsRelayerFactoryProxyAdmin admin = new DataStreamsRelayerFactoryProxyAdmin();
    bytes memory initData = abi.encodeWithSelector(
      IDataStreamsRelayerFactory.initialize.selector,
      sortedOracles,
      address(verifier),
      deployer
    );
    DataStreamsRelayerFactoryProxy proxy = new DataStreamsRelayerFactoryProxy(address(impl), address(admin), initData);
    IDataStreamsRelayerFactory factory = IDataStreamsRelayerFactory(address(proxy));

    // One single-leg relayer for the real rate feed. The leg feedId is arbitrary (the mock verifier
    // doesn't check it beyond the relayer's own feedId binding, which we mirror in the report).
    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](1);
    legs[0] = IDataStreamsRelayer.StreamLeg(keccak256("HARNESS:cUSD/cEUR"), false);
    address relayer = factory.deployRelayer(rateFeedId, "cUSD/cEUR (harness)", 0, 3600, legs);

    vm.stopBroadcast();

    // Parsed by script/fork-harness.sh
    console.log("HARNESS_MOCK_VERIFIER=%s", address(verifier));
    console.log("HARNESS_RELAYER_FACTORY=%s", address(factory));
    console.log("HARNESS_RELAYER=%s", relayer);
    console.log("HARNESS_LEG_FEED_ID=%s", vm.toString(keccak256("HARNESS:cUSD/cEUR")));
  }
}
