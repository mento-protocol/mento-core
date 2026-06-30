// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script, console } from "forge-std/Script.sol";

import { DataStreamsRelayerFactory } from "contracts/oracles/DataStreamsRelayerFactory.sol";
import { DataStreamsRelayerFactoryProxy } from "contracts/oracles/DataStreamsRelayerFactoryProxy.sol";
import { DataStreamsRelayerFactoryProxyAdmin } from "contracts/oracles/DataStreamsRelayerFactoryProxyAdmin.sol";
import { IDataStreamsRelayer } from "contracts/interfaces/IDataStreamsRelayer.sol";
import { IDataStreamsRelayerFactory } from "contracts/interfaces/IDataStreamsRelayerFactory.sol";

/**
 * @title DeployDataStreamsSepoliaForkTest
 * @notice TEMPORARY fork-test scaffold (not committed). Deploys the Data Streams factory pointed at
 *         the REAL Celo Sepolia VerifierProxy + the REAL Mento Sepolia SortedOracles, and one
 *         single-leg EUR/USD relayer. Unlike the mock harness, this verifies genuine DON signatures.
 * Env: DS_SORTED_ORACLES, DS_VERIFIER, DS_RATE_FEED, DS_LEG_FEED_ID, DS_MAX_STALENESS
 */
contract DeployDataStreamsSepoliaForkTest is Script {
  function run() public {
    address sortedOracles = vm.envAddress("DS_SORTED_ORACLES");
    address verifier = vm.envAddress("DS_VERIFIER");
    address rateFeedId = vm.envAddress("DS_RATE_FEED");
    bytes32 legFeedId = vm.envBytes32("DS_LEG_FEED_ID");
    uint256 maxStaleness = vm.envOr("DS_MAX_STALENESS", uint256(3600));
    address deployer = msg.sender;

    vm.startBroadcast(deployer);

    DataStreamsRelayerFactory impl = new DataStreamsRelayerFactory(true);
    DataStreamsRelayerFactoryProxyAdmin admin = new DataStreamsRelayerFactoryProxyAdmin();
    bytes memory initData = abi.encodeWithSelector(
      IDataStreamsRelayerFactory.initialize.selector,
      sortedOracles,
      verifier,
      deployer
    );
    DataStreamsRelayerFactoryProxy proxy = new DataStreamsRelayerFactoryProxy(address(impl), address(admin), initData);
    IDataStreamsRelayerFactory factory = IDataStreamsRelayerFactory(address(proxy));

    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](1);
    legs[0] = IDataStreamsRelayer.StreamLeg(legFeedId, false);
    address relayer = factory.deployRelayer(rateFeedId, "EUR/USD (sepolia fork test)", 0, maxStaleness, legs);

    vm.stopBroadcast();

    console.log("DSFT_FACTORY=%s", address(factory));
    console.log("DSFT_RELAYER=%s", relayer);
  }
}
