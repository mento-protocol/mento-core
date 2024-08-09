// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.18;

import { console } from "forge-std-next/console.sol";
import "../utils/BaseTest.next.sol";
import "../mocks/MockAggregatorV3.sol";
import "contracts/interfaces/IChainlinkRelayer.sol";
import { ChainlinkRelayerV1 } from "contracts/oracles/ChainlinkRelayerV1.sol";
import { ChainlinkRelayerV2 } from "contracts/oracles/ChainlinkRelayerV2.sol";

import { UD60x18, ud, intoUint256 } from "prb/math/UD60x18.sol";

interface ISortedOracles {
  function addOracle(address, address) external;

  function removeOracle(
    address,
    address,
    uint256
  ) external;

  function report(
    address,
    uint256,
    address,
    address
  ) external;

  function setTokenReportExpiry(address, uint256) external;

  function medianRate(address) external returns (uint256, uint256);

  function medianTimestamp(address token) external returns (uint256);
}

contract ChainlinkRelayerGasComparisonTest is BaseTest {
  ISortedOracles sortedOracles;

  MockAggregatorV3 chainlinkAggregator0;
  MockAggregatorV3 chainlinkAggregator1;
  MockAggregatorV3 chainlinkAggregator2;
  MockAggregatorV3 chainlinkAggregator3;
  bool invert0 = false;
  bool invert1 = true;
  bool invert2 = false;
  bool invert3 = true;

  int256 aggregatorPrice0;
  int256 aggregatorPrice1;
  int256 aggregatorPrice2;
  int256 aggregatorPrice3;
  uint256 expectedReport;
  uint256 aReport = 4100000000000000000000000;

  IChainlinkRelayer relayer0;
  IChainlinkRelayer relayer1;

  address rateFeedId0 = makeAddr("rateFeed0");
  address rateFeedId1 = makeAddr("rateFeed1");

  uint256 expirySeconds = 600;

  function setUpRelayer_single() internal {
    relayer0 = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId0,
        address(sortedOracles),
        0,
        address(chainlinkAggregator0),
        address(0),
        address(0),
        address(0),
        invert0,
        false,
        false,
        false
      )
    );
    relayer1 = IChainlinkRelayer(
      new ChainlinkRelayerV2(
        rateFeedId1,
        address(sortedOracles),
        0,
        address(chainlinkAggregator0),
        address(0),
        address(0),
        address(0),
        invert0,
        false,
        false,
        false
      )
    );
    sortedOracles.addOracle(rateFeedId0, address(relayer0));
    sortedOracles.addOracle(rateFeedId1, address(relayer1));
  }

  function setUpRelayer_double() internal {
    relayer0 = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId0,
        address(sortedOracles),
        100,
        address(chainlinkAggregator0),
        address(chainlinkAggregator1),
        address(0),
        address(0),
        invert0,
        invert1,
        false,
        false
      )
    );
    relayer1 = IChainlinkRelayer(
      new ChainlinkRelayerV2(
        rateFeedId1,
        address(sortedOracles),
        100,
        address(chainlinkAggregator0),
        address(chainlinkAggregator1),
        address(0),
        address(0),
        invert0,
        invert1,
        false,
        false
      )
    );
    sortedOracles.addOracle(rateFeedId0, address(relayer0));
    sortedOracles.addOracle(rateFeedId1, address(relayer1));
  }

  function setUpRelayer_triple() internal {
    relayer0 = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId0,
        address(sortedOracles),
        100,
        address(chainlinkAggregator0),
        address(chainlinkAggregator1),
        address(chainlinkAggregator2),
        address(0),
        invert0,
        invert1,
        invert2,
        false
      )
    );
    relayer1 = IChainlinkRelayer(
      new ChainlinkRelayerV2(
        rateFeedId1,
        address(sortedOracles),
        100,
        address(chainlinkAggregator0),
        address(chainlinkAggregator1),
        address(chainlinkAggregator2),
        address(0),
        invert0,
        invert1,
        invert2,
        false
      )
    );
    sortedOracles.addOracle(rateFeedId0, address(relayer0));
    sortedOracles.addOracle(rateFeedId1, address(relayer1));
  }

  function setUpRelayer_full() internal {
    relayer0 = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId0,
        address(sortedOracles),
        100,
        address(chainlinkAggregator0),
        address(chainlinkAggregator1),
        address(chainlinkAggregator2),
        address(chainlinkAggregator3),
        invert0,
        invert1,
        invert2,
        invert3
      )
    );
    relayer1 = IChainlinkRelayer(
      new ChainlinkRelayerV2(
        rateFeedId1,
        address(sortedOracles),
        100,
        address(chainlinkAggregator0),
        address(chainlinkAggregator1),
        address(chainlinkAggregator2),
        address(chainlinkAggregator3),
        invert0,
        invert1,
        invert2,
        invert3
      )
    );
    sortedOracles.addOracle(rateFeedId0, address(relayer0));
    sortedOracles.addOracle(rateFeedId1, address(relayer1));
  }

  function setUp() public virtual {
    sortedOracles = ISortedOracles(
      factory.createFromPath("contracts/common/SortedOracles.sol:SortedOracles", abi.encode(true), address(this))
    );
    sortedOracles.setTokenReportExpiry(rateFeedId0, expirySeconds);
    sortedOracles.setTokenReportExpiry(rateFeedId1, expirySeconds);

    chainlinkAggregator0 = new MockAggregatorV3(8);
    chainlinkAggregator1 = new MockAggregatorV3(12);
    chainlinkAggregator2 = new MockAggregatorV3(8);
    chainlinkAggregator3 = new MockAggregatorV3(6);
  }

  function setUpAggregators() public {
    chainlinkAggregator0.setRoundData(int256(aggregatorPrice0), uint256(block.timestamp));
    chainlinkAggregator1.setRoundData(int256(aggregatorPrice1), uint256(block.timestamp));
    chainlinkAggregator2.setRoundData(int256(aggregatorPrice2), uint256(block.timestamp));
    chainlinkAggregator3.setRoundData(int256(aggregatorPrice3), uint256(block.timestamp));
  }
}

contract ChainlinkRelayerGasComparisonTest_single is ChainlinkRelayerGasComparisonTest {
  function setUpRelayer() internal virtual {
    console.log("ChainlinkRelayer with 1 aggregator");
    setUpRelayer_single();
  }

  function setUpExpectations() internal {
    aggregatorPrice0 = 420000000; // 4.2 * 1e8
    aggregatorPrice1 = 2000000000000; // 2 * 1e12
    aggregatorPrice2 = 300000000; // 3 * 1e8
    aggregatorPrice3 = 5000000; // 5 * 1e6
    expectedReport = 1260000000000000000000000;
  }

  function setUp() public override {
    super.setUp();
    setUpRelayer();
    setUpExpectations();
    setUpAggregators();
  }

  function test_relayer0() public {
    uint256 gasLeftBefore = gasleft();
    relayer0.relay();
    uint256 gasLeftAfter = gasleft();
    uint256 relayerReportPrice = gasLeftBefore - gasLeftAfter;
    console.log("ChainlinkRelayerV1 gas cost: ", relayerReportPrice);
  }

  function test_relayer1() public {
    uint256 gasLeftBefore = gasleft();
    relayer1.relay();
    uint256 gasLeftAfter = gasleft();
    uint256 relayerReportPrice = gasLeftBefore - gasLeftAfter;
    console.log("ChainlinkRelayerV2 gas cost: ", relayerReportPrice);
  }
}

contract ChainlinkRelayerGasComparisonTest_double is ChainlinkRelayerGasComparisonTest_single {
  function setUpRelayer() internal override {
    console.log("ChainlinkRelayer with 2 aggregators");
    setUpRelayer_double();
  }
}

contract ChainlinkRelayerGasComparisonTest_triple is ChainlinkRelayerGasComparisonTest_single {
  function setUpRelayer() internal override {
    console.log("ChainlinkRelayer with 3 aggregators");
    setUpRelayer_triple();
  }
}

contract ChainlinkRelayerGasComparisonTest_full is ChainlinkRelayerGasComparisonTest_single {
  function setUpRelayer() internal override {
    console.log("ChainlinkRelayer with 4 aggregators");
    setUpRelayer_full();
  }
}
