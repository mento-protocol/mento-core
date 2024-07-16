// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import "../utils/BaseTest.t.sol";
import "contracts/common/SortedOracles.sol";
import "../mocks/MockAggregatorV3.sol";
import "contracts/interfaces/IChainlinkRelayer.sol";

contract ChainlinkRelayerTest is BaseTest {
  bytes constant TIMESTAMP_NOT_NEW_ERROR = abi.encodeWithSignature("TimestampNotNew()");
  bytes constant EXPIRED_TIMESTAMP_ERROR = abi.encodeWithSignature("ExpiredTimestamp()");
  bytes constant NEGATIVE_PRICE_ERROR = abi.encodeWithSignature("NegativePrice()");
  SortedOracles sortedOracles;
  MockAggregatorV3 chainlinkAggregator;
  IChainlinkRelayer relayer;
  address rateFeedId = actor("rateFeed");
  int256 aPrice = 420000000;
  uint256 expectedReport = 4200000000000000000000000;
  uint256 aReport = 4100000000000000000000000;
  uint256 expirySeconds = 600;

  function setUp() public {
    sortedOracles = new SortedOracles(true);
    chainlinkAggregator = new MockAggregatorV3();
    relayer = IChainlinkRelayer(
      factory.createContract(
        "ChainlinkRelayerV1",
        abi.encode(rateFeedId, address(sortedOracles), address(chainlinkAggregator))
      )
    );
    sortedOracles.addOracle(rateFeedId, address(relayer));
    sortedOracles.setTokenReportExpiry(rateFeedId, expirySeconds);
  }
}

contract ChainlinkRelayerTest_constructor is ChainlinkRelayerTest {
  function test_constructorSetsRateFeedId() public {
    address _rateFeedId = relayer.rateFeedId();
    assertEq(_rateFeedId, rateFeedId);
  }

  function test_constructorSetsSortedOracles() public {
    address _sortedOracles = relayer.sortedOracles();
    assertEq(_sortedOracles, address(sortedOracles));
  }

  function test_constructorSetsAggregator() public {
    address _chainlinkAggregator = relayer.chainlinkAggregator();
    assertEq(_chainlinkAggregator, address(chainlinkAggregator));
  }
}

contract ChainlinkRelayerTest_relay is ChainlinkRelayerTest {
  function setUp() public {
    super.setUp();
    chainlinkAggregator.setRoundData(int256(aPrice), uint256(block.timestamp));
  }

  function test_relaysTheRate() public {
    relayer.relay();
    (uint256 medianRate, ) = sortedOracles.medianRate(rateFeedId);
    assertEq(medianRate, expectedReport);
  }

  function testFuzz_convertsChainlinkToFixidityCorrectly(int256 x) public {
    vm.assume(x >= 0);
    vm.assume(uint256(x) < uint256(2**256 - 1) / (10**(24 - 8)));
    chainlinkAggregator.setRoundData(x, uint256(block.timestamp));
    relayer.relay();
    (uint256 medianRate, ) = sortedOracles.medianRate(rateFeedId);
    assertEq(medianRate, uint256(x) * 10**(24 - 8));
  }

  function test_revertsOnNegativePrice() public {
    chainlinkAggregator.setRoundData(-1 * aPrice, block.timestamp);
    vm.expectRevert(NEGATIVE_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnEarlierTimestamp() public {
    vm.prank(address(relayer));
    sortedOracles.report(rateFeedId, aReport, address(0), address(0));
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);
    chainlinkAggregator.setRoundData(aPrice, latestTimestamp - 1);
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_revertsOnRepeatTimestamp() public {
    vm.prank(address(relayer));
    sortedOracles.report(rateFeedId, aReport, address(0), address(0));
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);
    chainlinkAggregator.setRoundData(aPrice, latestTimestamp);
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_revertsOnExpiredTimestamp() public {
    vm.prank(address(relayer));
    sortedOracles.report(rateFeedId, aReport, address(0), address(0));
    chainlinkAggregator.setRoundData(aPrice, block.timestamp + 1);
    vm.warp(block.timestamp + expirySeconds + 1);
    vm.expectRevert(EXPIRED_TIMESTAMP_ERROR);
    relayer.relay();
  }

  function test_revertsWhenFirstTimestampIsExpired() public {
    chainlinkAggregator.setRoundData(aPrice, block.timestamp);
    vm.warp(block.timestamp + expirySeconds);
    vm.expectRevert(EXPIRED_TIMESTAMP_ERROR);
    relayer.relay();
  }
}
