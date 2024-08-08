// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility,
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Ownable } from "openzeppelin-contracts/ownership/Ownable.sol";

import { IntegrationTest } from "../utils/IntegrationTest.t.sol";
import { MockAggregatorV3 } from "../mocks/MockAggregatorV3.sol";

import { IChainlinkRelayerFactory } from "contracts/interfaces/IChainlinkRelayerFactory.sol";
import { IChainlinkRelayer } from "contracts/interfaces/IChainlinkRelayer.sol";
import { IProxyAdmin } from "contracts/interfaces/IProxyAdmin.sol";
import { ITransparentProxy } from "contracts/interfaces/ITransparentProxy.sol";

contract ChainlinkRelayerIntegration is IntegrationTest {
  address owner = actor("owner");

  IChainlinkRelayerFactory relayerFactoryImplementation;
  IChainlinkRelayerFactory relayerFactory;
  IProxyAdmin proxyAdmin;
  ITransparentProxy proxy;

  function setUp() public {
    IntegrationTest.setUp();

    proxyAdmin = IProxyAdmin(factory.createContract("ChainlinkRelayerFactoryProxyAdmin", ""));
    relayerFactoryImplementation = IChainlinkRelayerFactory(
      factory.createContract("ChainlinkRelayerFactory", abi.encode(true))
    );
    proxy = ITransparentProxy(
      factory.createContract(
        "ChainlinkRelayerFactoryProxy",
        abi.encode(
          address(relayerFactoryImplementation),
          address(proxyAdmin),
          abi.encodeWithSignature("initialize(address)", address(sortedOracles))
        )
      )
    );
    relayerFactory = IChainlinkRelayerFactory(address(proxy));
    vm.startPrank(address(factory));
    Ownable(address(proxyAdmin)).transferOwnership(owner);
    Ownable(address(relayerFactory)).transferOwnership(owner);
    vm.stopPrank();
  }
}

contract ChainlinkRelayerIntegration_ProxySetup is ChainlinkRelayerIntegration {
  function test_proxyOwnedByAdmin() public {
    address admin = proxyAdmin.getProxyAdmin(address(proxy));
    assertEq(admin, address(proxyAdmin));
  }

  function test_adminOwnedByOwner() public {
    address realOwner = Ownable(address(proxyAdmin)).owner();
    assertEq(realOwner, owner);
  }

  function test_adminCantCallImplementation() public {
    vm.prank(address(proxyAdmin));
    vm.expectRevert("TransparentUpgradeableProxy: admin cannot fallback to proxy target");
    relayerFactory.sortedOracles();
  }

  function test_nonAdminCantCallProxy() public {
    vm.prank(owner);
    vm.expectRevert();
    proxy.implementation();
  }

  function test_implementationOwnedByOwner() public {
    address realOwner = Ownable(address(relayerFactory)).owner();
    assertEq(realOwner, owner);
  }

  function test_implementationSetCorrectly() public {
    address implementation = proxyAdmin.getProxyImplementation(address(proxy));
    assertEq(implementation, address(relayerFactoryImplementation));
  }

  function test_implementationNotInitializable() public {
    vm.expectRevert("Initializable: contract is already initialized");
    relayerFactoryImplementation.initialize(address(sortedOracles));
  }
}

contract ChainlinkRelayerIntegration_CircuitBreakerInteraction is ChainlinkRelayerIntegration {
  // Fictional rate feed ID
  address rateFeedId = address(bytes20(keccak256(("cUSD/FOO"))));

  MockAggregatorV3 chainlinkAggregator;
  IChainlinkRelayer chainlinkRelayer;

  function setUp() public {
    super.setUp();

    setUpRelayer();
    setUpCircuitBreaker();
  }

  function setUpRelayer() public {
    chainlinkAggregator = new MockAggregatorV3();
    vm.prank(owner);
    chainlinkRelayer = IChainlinkRelayer(relayerFactory.deployRelayer(rateFeedId, address(chainlinkAggregator)));

    vm.prank(deployer);
    sortedOracles.addOracle(rateFeedId, address(chainlinkRelayer));
  }

  function setUpCircuitBreaker() public {
    setUpBreakerBox();
    setUpBreaker();
  }

  function setUpBreakerBox() public {
    vm.startPrank(deployer);
    breakerBox.addRateFeed(rateFeedId);
    breakerBox.toggleBreaker(address(valueDeltaBreaker), rateFeedId, true);
    vm.stopPrank();
  }

  function setUpBreaker() public {
    address[] memory rateFeeds = new address[](1);
    rateFeeds[0] = rateFeedId;
    uint256[] memory thresholds = new uint256[](1);
    thresholds[0] = 10**23; // 10%
    uint256[] memory cooldownTimes = new uint256[](1);
    cooldownTimes[0] = 1 minutes;
    uint256[] memory referenceValues = new uint256[](1);
    referenceValues[0] = 10**24;

    vm.startPrank(deployer);
    valueDeltaBreaker.setRateChangeThresholds(rateFeeds, thresholds);
    valueDeltaBreaker.setCooldownTimes(rateFeeds, cooldownTimes);
    valueDeltaBreaker.setReferenceValues(rateFeeds, referenceValues);
    vm.stopPrank();
  }

  function test_initiallyNoPrice() public {
    (uint256 price, uint256 denominator) = sortedOracles.medianRate(rateFeedId);
    uint8 tradingMode = breakerBox.getRateFeedTradingMode(rateFeedId);
    assertEq(price, 0);
    assertEq(denominator, 0);
    assertEq(uint256(tradingMode), 0);
  }

  function test_passesPriceFromAggregatorToSortedOracles() public {
    chainlinkAggregator.setRoundData(10**8, block.timestamp - 1);
    chainlinkRelayer.relay();
    (uint256 price, uint256 denominator) = sortedOracles.medianRate(rateFeedId);
    uint8 tradingMode = breakerBox.getRateFeedTradingMode(rateFeedId);
    assertEq(price, 10**24);
    assertEq(denominator, 10**24);
    assertEq(uint256(tradingMode), 0);
  }

  function test_whenPriceBeyondThresholdIsRelayed_breakerShouldTrigger() public {
    chainlinkAggregator.setRoundData(12 * 10**7, block.timestamp - 1);
    chainlinkRelayer.relay();
    (uint256 price, uint256 denominator) = sortedOracles.medianRate(rateFeedId);
    uint8 tradingMode = breakerBox.getRateFeedTradingMode(rateFeedId);
    assertEq(price, 12 * 10**23);
    assertEq(denominator, 10**24);
    assertEq(uint256(tradingMode), 3);
  }

  function test_whenPriceBeyondThresholdIsRelayedThenRecovers_breakerShouldTriggerThenRecover() public {
    chainlinkAggregator.setRoundData(12 * 10**7, block.timestamp - 1);
    chainlinkRelayer.relay();
    uint8 tradingMode = breakerBox.getRateFeedTradingMode(rateFeedId);
    assertEq(uint256(tradingMode), 3);

    vm.warp(now + 1 minutes + 1);

    chainlinkAggregator.setRoundData(105 * 10**6, block.timestamp - 1);
    chainlinkRelayer.relay();
    (uint256 price, uint256 denominator) = sortedOracles.medianRate(rateFeedId);
    tradingMode = breakerBox.getRateFeedTradingMode(rateFeedId);
    assertEq(price, 105 * 10**22);
    assertEq(denominator, 10**24);
    assertEq(uint256(tradingMode), 0);
  }

  function test_whenPriceBeyondThresholdIsRelayedAndCooldownIsntReached_breakerShouldTriggerAndNotRecover() public {
    chainlinkAggregator.setRoundData(12 * 10**7, block.timestamp - 1);
    chainlinkRelayer.relay();
    uint8 tradingMode = breakerBox.getRateFeedTradingMode(rateFeedId);
    assertEq(uint256(tradingMode), 3);

    vm.warp(now + 1 minutes - 1);

    chainlinkAggregator.setRoundData(105 * 10**6, block.timestamp - 1);
    chainlinkRelayer.relay();
    (uint256 price, uint256 denominator) = sortedOracles.medianRate(rateFeedId);
    tradingMode = breakerBox.getRateFeedTradingMode(rateFeedId);
    assertEq(price, 105 * 10**22);
    assertEq(denominator, 10**24);
    assertEq(uint256(tradingMode), 3);
  }
}
