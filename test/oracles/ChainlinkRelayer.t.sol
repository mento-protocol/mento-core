// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.18;

import "../utils/BaseTest.next.sol";
import "../mocks/MockAggregatorV3.sol";
import "contracts/interfaces/IChainlinkRelayer.sol";
import "contracts/oracles/ChainlinkRelayerV1.sol";

import { UD60x18, ud, intoUint256 } from "@prb/math/src/UD60x18.sol";

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

contract ChainlinkRelayerTest is BaseTest {
  bytes constant TIMESTAMP_NOT_NEW_ERROR = abi.encodeWithSignature("TimestampNotNew()");
  bytes constant EXPIRED_TIMESTAMP_ERROR = abi.encodeWithSignature("ExpiredTimestamp()");
  bytes constant INVALID_PRICE_ERROR = abi.encodeWithSignature("InvalidPrice()");
  bytes constant TIMESTAMP_SPREAD_TOO_HIGH = abi.encodeWithSignature("TimestampSpreadTooHigh()");
  bytes constant PRICE_PATH_HAS_GAPS = abi.encodeWithSignature("PricePathHasGaps()");

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

  IChainlinkRelayer relayer;
  address rateFeedId = makeAddr("rateFeed");
  uint256 expirySeconds = 600;

  function setUpRelayer_single() internal {
    relayer = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId,
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
    sortedOracles.addOracle(rateFeedId, address(relayer));
  }

  function setUpRelayer_double() internal {
    relayer = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId,
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
    sortedOracles.addOracle(rateFeedId, address(relayer));
  }

  function setUpRelayer_triple() internal {
    relayer = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId,
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
    sortedOracles.addOracle(rateFeedId, address(relayer));
  }

  function setUpRelayer_full() internal {
    relayer = IChainlinkRelayer(
      new ChainlinkRelayerV1(
        rateFeedId,
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
    sortedOracles.addOracle(rateFeedId, address(relayer));
  }

  function setUp() public virtual {
    sortedOracles = ISortedOracles(
      factory.createFromPath("contracts/common/SortedOracles.sol:SortedOracles", abi.encode(true), address(this))
    );
    sortedOracles.setTokenReportExpiry(rateFeedId, expirySeconds);

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

contract ChainlinkRelayerTest_constructor_invalid is ChainlinkRelayerTest {
  function test_constructorRevertsWhenPathInvalid() public {
    vm.expectRevert(PRICE_PATH_HAS_GAPS);
    new ChainlinkRelayerV1(
      rateFeedId,
      address(sortedOracles),
      1000,
      address(chainlinkAggregator0),
      address(0),
      address(chainlinkAggregator3),
      address(0),
      false,
      false,
      false,
      false
    );
    vm.expectRevert(PRICE_PATH_HAS_GAPS);
    new ChainlinkRelayerV1(
      rateFeedId,
      address(sortedOracles),
      1000,
      address(chainlinkAggregator0),
      address(0),
      address(0),
      address(chainlinkAggregator3),
      false,
      false,
      false,
      false
    );
    vm.expectRevert(PRICE_PATH_HAS_GAPS);
    new ChainlinkRelayerV1(
      rateFeedId,
      address(sortedOracles),
      1000,
      address(0),
      address(chainlinkAggregator0),
      address(0),
      address(chainlinkAggregator3),
      false,
      false,
      false,
      false
    );
    vm.expectRevert(PRICE_PATH_HAS_GAPS);
    new ChainlinkRelayerV1(
      rateFeedId,
      address(sortedOracles),
      1000,
      address(0),
      address(0),
      address(chainlinkAggregator0),
      address(chainlinkAggregator3),
      false,
      false,
      false,
      false
    );
  }
}

contract ChainlinkRelayerTest_constructor_single is ChainlinkRelayerTest {
  function setUpRelayer() internal virtual {
    setUpRelayer_single();
  }

  function setUp() public override {
    super.setUp();
    setUpRelayer();
  }

  function test_constructorSetsRateFeedId() public {
    address _rateFeedId = relayer.rateFeedId();
    assertEq(_rateFeedId, rateFeedId);
  }

  function test_constructorSetsSortedOracles() public {
    address _sortedOracles = relayer.sortedOracles();
    assertEq(_sortedOracles, address(sortedOracles));
  }

  function test_constructorSetsAggregators() public virtual {
    IChainlinkRelayer.Config memory config = relayer.getConfig();
    assertEq(config.chainlinkAggregator0, address(chainlinkAggregator0));
    assertEq(config.chainlinkAggregator1, address(0));
    assertEq(config.chainlinkAggregator2, address(0));
    assertEq(config.chainlinkAggregator3, address(0));
    assertEq(config.invertAggregator0, invert0);
    assertEq(config.invertAggregator1, false);
    assertEq(config.invertAggregator2, false);
    assertEq(config.invertAggregator3, false);
  }
}

contract ChainlinkRelayerTest_constructor_double is ChainlinkRelayerTest_constructor_single {
  function setUpRelayer() internal override {
    setUpRelayer_double();
  }

  function test_constructorSetsAggregators() public override {
    IChainlinkRelayer.Config memory config = relayer.getConfig();
    assertEq(config.chainlinkAggregator0, address(chainlinkAggregator0));
    assertEq(config.chainlinkAggregator1, address(chainlinkAggregator1));
    assertEq(config.chainlinkAggregator2, address(0));
    assertEq(config.chainlinkAggregator3, address(0));
    assertEq(config.invertAggregator0, invert0);
    assertEq(config.invertAggregator1, invert1);
    assertEq(config.invertAggregator2, false);
    assertEq(config.invertAggregator3, false);
  }
}

contract ChainlinkRelayerTest_constructor_triple is ChainlinkRelayerTest_constructor_single {
  function setUpRelayer() internal override {
    setUpRelayer_triple();
  }

  function test_constructorSetsAggregators() public override {
    IChainlinkRelayer.Config memory config = relayer.getConfig();
    assertEq(config.chainlinkAggregator0, address(chainlinkAggregator0));
    assertEq(config.chainlinkAggregator1, address(chainlinkAggregator1));
    assertEq(config.chainlinkAggregator2, address(chainlinkAggregator2));
    assertEq(config.chainlinkAggregator3, address(0));
    assertEq(config.invertAggregator0, invert0);
    assertEq(config.invertAggregator1, invert1);
    assertEq(config.invertAggregator2, invert2);
    assertEq(config.invertAggregator3, false);
  }
}

contract ChainlinkRelayerTest_constructor_full is ChainlinkRelayerTest_constructor_single {
  function setUpRelayer() internal override {
    setUpRelayer_full();
  }

  function test_constructorSetsAggregators() public override {
    IChainlinkRelayer.Config memory config = relayer.getConfig();
    assertEq(config.chainlinkAggregator0, address(chainlinkAggregator0));
    assertEq(config.chainlinkAggregator1, address(chainlinkAggregator1));
    assertEq(config.chainlinkAggregator2, address(chainlinkAggregator2));
    assertEq(config.chainlinkAggregator3, address(chainlinkAggregator3));
    assertEq(config.invertAggregator0, invert0);
    assertEq(config.invertAggregator1, invert1);
    assertEq(config.invertAggregator2, invert2);
    assertEq(config.invertAggregator3, invert3);
  }
}

contract ChainlinkRelayerTest_fuzz_single is ChainlinkRelayerTest {
  function setUp() public override {
    super.setUp();
    setUpRelayer_single();
  }

  function testFuzz_convertsChainlinkToUD60x18Correctly(int256 x) public {
    vm.assume(x > 0);
    vm.assume(uint256(x) < uint256(2**256 - 1) / (10**(24 - 8)));
    chainlinkAggregator0.setRoundData(x, uint256(block.timestamp));
    relayer.relay();
    (uint256 medianRate, ) = sortedOracles.medianRate(rateFeedId);
    assertEq(medianRate, uint256(x) * 10**(24 - 8));
  }
}

contract ChainlinkRelayerTest_fuzz_full is ChainlinkRelayerTest {
  function setUp() public override {
    super.setUp();
    setUpRelayer_full();
  }

  function testFuzz_calculatesReportsCorrectly(
    int256 _aggregatorPrice0,
    int256 _aggregatorPrice1,
    int256 _aggregatorPrice2,
    int256 _aggregatorPrice3,
    bool _invert0,
    bool _invert1,
    bool _invert2,
    bool _invert3
  ) public {
    vm.assume(_aggregatorPrice0 > 0);
    vm.assume(_aggregatorPrice1 > 0);
    vm.assume(_aggregatorPrice2 > 0);
    vm.assume(_aggregatorPrice3 > 0);
    vm.assume(_aggregatorPrice0 <= 1e5 * 1e6); // sane max for a price source
    vm.assume(_aggregatorPrice1 <= 1e5 * 1e6); // sane max for a price source
    vm.assume(_aggregatorPrice2 <= 1e5 * 1e6); // sane max for a price source
    vm.assume(_aggregatorPrice3 <= 1e5 * 1e6); // sane max for a price source

    aggregatorPrice0 = _aggregatorPrice0;
    aggregatorPrice1 = _aggregatorPrice1;
    aggregatorPrice2 = _aggregatorPrice2;
    aggregatorPrice3 = _aggregatorPrice3;
    invert0 = _invert0;
    invert1 = _invert1;
    invert2 = _invert2;
    invert3 = _invert3;

    setUpRelayer_full();
    setUpAggregators();

    relayer.relay();
    (uint256 medianRate, ) = sortedOracles.medianRate(rateFeedId);
    assertEq(medianRate, expectedPriceInFixidity());
  }

  function expectedPriceInFixidity() internal view returns (uint256) {
    UD60x18 price0 = ud(uint256(aggregatorPrice0) * 1e10);
    if (invert0) {
      price0 = ud(1e18).div(price0);
    }
    UD60x18 price1 = ud(uint256(aggregatorPrice1) * 1e6);
    if (invert1) {
      price1 = ud(1e18).div(price1);
    }
    UD60x18 price2 = ud(uint256(aggregatorPrice2) * 1e10);
    if (invert2) {
      price2 = ud(1e18).div(price2);
    }
    UD60x18 price3 = ud(uint256(aggregatorPrice3) * 1e12);
    if (invert3) {
      price3 = ud(1e18).div(price3);
    }
    return intoUint256(price0.mul(price1).mul(price2).mul(price3)) * 1e6; // 1e18 -> 1e24
  }
}

contract ChainlinkRelayerTest_relay_single is ChainlinkRelayerTest {
  modifier withReport(uint256 report) {
    vm.warp(2);
    vm.prank(address(relayer));
    sortedOracles.report(rateFeedId, report, address(0), address(0));
    _;
  }

  function setUpRelayer() internal virtual {
    setUpRelayer_single();
  }

  function setUpExpectations() internal virtual {
    aggregatorPrice0 = 420000000;
    expectedReport = 4200000000000000000000000;
  }

  function setUp() public override {
    super.setUp();
    setUpRelayer();
    setUpExpectations();
    setUpAggregators();
  }

  function test_relaysTheRate() public {
    relayer.relay();
    (uint256 medianRate, ) = sortedOracles.medianRate(rateFeedId);
    assertEq(medianRate, expectedReport);
  }

  function test_revertsOnNegativePrice0() public {
    chainlinkAggregator0.setRoundData(-1 * aggregatorPrice0, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnZeroPrice0() public {
    chainlinkAggregator0.setRoundData(0, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnEarlierTimestamp() public virtual withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);
    chainlinkAggregator0.setRoundData(aggregatorPrice0, latestTimestamp - 1);
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_relaysOnRecentTimestamp0() public withReport(aReport) {
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
    skip(50);
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp);
    relayer.relay();
    uint256 timestamp = sortedOracles.medianTimestamp(rateFeedId);
    assertEq(timestamp, block.timestamp);
  }

  function test_revertsOnRepeatTimestamp0() public withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);
    chainlinkAggregator0.setRoundData(aggregatorPrice0, latestTimestamp);
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_revertsWhenMostRecentTimestampIsExpired() public virtual withReport(aReport) {
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp + 1);
    vm.warp(block.timestamp + expirySeconds + 1);
    vm.expectRevert(EXPIRED_TIMESTAMP_ERROR);
    relayer.relay();
  }
}

contract ChainlinkRelayerTest_relay_double is ChainlinkRelayerTest_relay_single {
  function setUpExpectations() internal virtual override {
    aggregatorPrice0 = 420000000; // 4.2 * 1e8
    aggregatorPrice1 = 2000000000000; // 2 * 1e12
    // ^ results in 4.2 * 1 / 2 = 2.1
    expectedReport = 2100000000000000000000000;
  }

  function setUpRelayer() internal virtual override {
    setUpRelayer_double();
  }

  function test_revertsOnNegativePrice1() public {
    chainlinkAggregator1.setRoundData(-1 * aggregatorPrice1, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnZeroPrice1() public {
    chainlinkAggregator1.setRoundData(0, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnEarlierTimestamp() public virtual override withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);

    chainlinkAggregator0.setRoundData(aggregatorPrice0, latestTimestamp - 1);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, latestTimestamp - 1);

    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_relaysOnRecentTimestamp1() public withReport(aReport) {
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
    skip(50);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, block.timestamp);
    relayer.relay();
    uint256 timestamp = sortedOracles.medianTimestamp(rateFeedId);
    assertEq(timestamp, block.timestamp);
  }

  function test_revertsOnRepeatTimestamp1() public withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, latestTimestamp);
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_revertsWhenMostRecentTimestampIsExpired() public virtual override withReport(aReport) {
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp + 1);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, block.timestamp + 1);
    vm.warp(block.timestamp + expirySeconds + 1);
    vm.expectRevert(EXPIRED_TIMESTAMP_ERROR);
    relayer.relay();
  }

  function test_revertsWhenTimestampSpreadTooLarge() public virtual {
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp);
    vm.warp(block.timestamp + 101);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, block.timestamp);
    vm.expectRevert(TIMESTAMP_SPREAD_TOO_HIGH);
    relayer.relay();
  }
}

contract ChainlinkRelayerTest_relay_triple is ChainlinkRelayerTest_relay_double {
  function setUpExpectations() internal virtual override {
    aggregatorPrice0 = 420000000; // 4.2 * 1e8
    aggregatorPrice1 = 2000000000000; // 2 * 1e12
    aggregatorPrice2 = 300000000; // 3 * 1e8
    // ^ results in 4.2 * (1 / 2) * 3 = 6.3
    expectedReport = 6300000000000000000000000;
  }

  function setUpRelayer() internal virtual override {
    setUpRelayer_triple();
  }

  function test_revertsOnNegativePrice2() public {
    chainlinkAggregator2.setRoundData(-1 * aggregatorPrice2, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnZeroPrice2() public {
    chainlinkAggregator2.setRoundData(0, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnEarlierTimestamp() public virtual override withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);

    chainlinkAggregator0.setRoundData(aggregatorPrice0, latestTimestamp - 1);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, latestTimestamp - 1);
    chainlinkAggregator2.setRoundData(aggregatorPrice2, latestTimestamp - 1);

    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_relaysOnRecentTimestamp2() public withReport(aReport) {
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
    skip(50);
    chainlinkAggregator2.setRoundData(aggregatorPrice0, block.timestamp);
    relayer.relay();
    uint256 timestamp = sortedOracles.medianTimestamp(rateFeedId);
    assertEq(timestamp, block.timestamp);
  }

  function test_revertsOnRepeatTimestamp2() public withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);
    chainlinkAggregator2.setRoundData(aggregatorPrice2, latestTimestamp);
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_revertsWhenMostRecentTimestampIsExpired() public virtual override withReport(aReport) {
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp + 1);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, block.timestamp + 1);
    chainlinkAggregator2.setRoundData(aggregatorPrice2, block.timestamp + 1);
    vm.warp(block.timestamp + expirySeconds + 1);
    vm.expectRevert(EXPIRED_TIMESTAMP_ERROR);
    relayer.relay();
  }

  function test_revertsWhenTimestampSpreadTooLarge() public virtual override {
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp);
    vm.warp(block.timestamp + 101);
    chainlinkAggregator2.setRoundData(aggregatorPrice2, block.timestamp);
    vm.expectRevert(TIMESTAMP_SPREAD_TOO_HIGH);
    relayer.relay();
  }
}

contract ChainlinkRelayerTest_relay_full is ChainlinkRelayerTest_relay_triple {
  function setUpExpectations() internal override {
    aggregatorPrice0 = 420000000; // 4.2 * 1e8
    aggregatorPrice1 = 2000000000000; // 2 * 1e12
    aggregatorPrice2 = 300000000; // 3 * 1e8
    aggregatorPrice3 = 5000000; // 5 * 1e6
    // ^ results in 4.2 * (1 / 2) * 3 * (1/5) = 1.26
    // in the tests price1 and price3 are inverted
    expectedReport = 1260000000000000000000000;
  }

  function setUpRelayer() internal override {
    setUpRelayer_full();
  }

  function test_revertsOnNegativePrice3() public {
    chainlinkAggregator3.setRoundData(-1 * aggregatorPrice3, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnZeroPrice3() public {
    chainlinkAggregator3.setRoundData(0, block.timestamp);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relayer.relay();
  }

  function test_revertsOnEarlierTimestamp() public override withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);

    chainlinkAggregator0.setRoundData(aggregatorPrice0, latestTimestamp - 1);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, latestTimestamp - 1);
    chainlinkAggregator2.setRoundData(aggregatorPrice2, latestTimestamp - 1);
    chainlinkAggregator3.setRoundData(aggregatorPrice3, latestTimestamp - 1);

    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_relaysOnRecentTimestamp3() public withReport(aReport) {
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
    skip(50);
    chainlinkAggregator3.setRoundData(aggregatorPrice3, block.timestamp);
    relayer.relay();
    uint256 timestamp = sortedOracles.medianTimestamp(rateFeedId);
    assertEq(timestamp, block.timestamp);
  }

  function test_revertsOnRepeatTimestamp3() public withReport(aReport) {
    uint256 latestTimestamp = sortedOracles.medianTimestamp(rateFeedId);
    chainlinkAggregator3.setRoundData(aggregatorPrice3, latestTimestamp);
    vm.expectRevert(TIMESTAMP_NOT_NEW_ERROR);
    relayer.relay();
  }

  function test_revertsWhenMostRecentTimestampIsExpired() public override withReport(aReport) {
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp + 1);
    chainlinkAggregator1.setRoundData(aggregatorPrice1, block.timestamp + 1);
    chainlinkAggregator2.setRoundData(aggregatorPrice2, block.timestamp + 1);
    chainlinkAggregator2.setRoundData(aggregatorPrice3, block.timestamp + 1);

    vm.warp(block.timestamp + expirySeconds + 1);
    vm.expectRevert(EXPIRED_TIMESTAMP_ERROR);
    relayer.relay();
  }

  function test_revertsWhenTimestampSpreadTooLarge() public virtual override {
    chainlinkAggregator0.setRoundData(aggregatorPrice0, block.timestamp);
    vm.warp(block.timestamp + 101);
    chainlinkAggregator3.setRoundData(aggregatorPrice3, block.timestamp);
    vm.expectRevert(TIMESTAMP_SPREAD_TOO_HIGH);
    relayer.relay();
  }
}
