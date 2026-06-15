// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.19;

import { Test } from "mento-std/Test.sol";

import { MockVerifierProxy } from "test/utils/mocks/MockVerifierProxy.sol";
import { IDataStreamsRelayer } from "contracts/interfaces/IDataStreamsRelayer.sol";
import { DataStreamsRelayerV1 } from "contracts/oracles/DataStreamsRelayerV1.sol";

import { UD60x18, ud, intoUint256 } from "prb/math/UD60x18.sol";

interface ISortedOracles {
  function initialize(uint256) external;

  function addOracle(address, address) external;

  function report(address, uint256, address, address) external;

  function setTokenReportExpiry(address, uint256) external;

  function medianRate(address) external returns (uint256, uint256);

  function medianTimestamp(address token) external returns (uint256);

  function getRates(address rateFeedId) external returns (address[] memory, uint256[] memory, uint256[] memory);
}

contract DataStreamsRelayerV1Test is Test {
  // Errors
  bytes constant NO_LEGS_ERROR = abi.encodeWithSignature("NoLegs()");
  bytes constant TOO_MANY_LEGS_ERROR = abi.encodeWithSignature("TooManyLegs()");
  bytes constant INVALID_MAX_TIMESTAMP_SPREAD_ERROR = abi.encodeWithSignature("InvalidMaxTimestampSpread()");
  bytes constant INVALID_FEED_ID_ERROR = abi.encodeWithSignature("InvalidFeedId()");
  bytes constant LEG_COUNT_MISMATCH_ERROR = abi.encodeWithSignature("LegCountMismatch()");
  bytes constant INVALID_PRICE_ERROR = abi.encodeWithSignature("InvalidPrice()");
  bytes constant EXPIRED_SIGNATURE_ERROR = abi.encodeWithSignature("ExpiredSignature()");
  bytes constant REPORT_TOO_STALE_ERROR = abi.encodeWithSignature("ReportTooStale()");
  bytes constant TIMESTAMP_SPREAD_TOO_HIGH_ERROR = abi.encodeWithSignature("TimestampSpreadTooHigh()");
  bytes constant STALE_REPORT_ERROR = abi.encodeWithSignature("StaleReport()");
  bytes constant REPORT_TOO_SHORT_ERROR = abi.encodeWithSignature("ReportTooShort()");

  event Relayed(address indexed rateFeedId, uint256 rate, uint256 observationsTimestamp, address indexed via);
  event ReportSkippedIdempotent(uint256 observationsTimestamp);

  ISortedOracles sortedOracles;
  MockVerifierProxy verifierProxy;
  IDataStreamsRelayer relayer;

  address rateFeedId = makeAddr("CELO/PHP");
  address caller = makeAddr("caller");

  bytes32 feedId0 = keccak256("CELO/USD");
  bytes32 feedId1 = keccak256("PHP/USD");
  bytes32 feedId2 = keccak256("USD/EUR");
  bytes32 feedId3 = keccak256("GBP/USD");

  bool invert0 = false;
  bool invert1 = true;
  bool invert2 = false;
  bool invert3 = true;

  uint256 expirySeconds = 3600;
  uint256 maxStaleness = 600;

  function setUp() public virtual {
    vm.warp(100_000); // ensure block.timestamp is comfortably > any observationsTimestamp we use
    sortedOracles = ISortedOracles(deployCode("SortedOracles", abi.encode(true)));
    sortedOracles.initialize(expirySeconds);
    sortedOracles.setTokenReportExpiry(rateFeedId, expirySeconds);
    verifierProxy = new MockVerifierProxy();
  }

  function setUpRelayer(uint256 legCount, uint256 maxTimestampSpread) internal {
    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](legCount);
    legs[0] = IDataStreamsRelayer.StreamLeg(feedId0, invert0);
    if (legCount > 1) legs[1] = IDataStreamsRelayer.StreamLeg(feedId1, invert1);
    if (legCount > 2) legs[2] = IDataStreamsRelayer.StreamLeg(feedId2, invert2);
    if (legCount > 3) legs[3] = IDataStreamsRelayer.StreamLeg(feedId3, invert3);

    relayer = IDataStreamsRelayer(
      new DataStreamsRelayerV1(
        rateFeedId,
        "CELO/PHP",
        address(sortedOracles),
        address(verifierProxy),
        maxTimestampSpread,
        maxStaleness,
        legs
      )
    );
    sortedOracles.addOracle(rateFeedId, address(relayer));
  }

  /// @notice Build a V3-shaped Data Streams report. The decoder only reads
  ///         feedId / observationsTimestamp / expiresAt / price; trailing fields are ignored.
  function buildReport(
    bytes32 feedId,
    uint32 observationsTimestamp,
    uint32 expiresAt,
    int192 price
  ) internal pure returns (bytes memory) {
    return
      abi.encode(
        feedId, // feedId
        uint32(0), // validFromTimestamp
        observationsTimestamp, // observationsTimestamp
        uint192(0), // nativeFee
        uint192(0), // linkFee
        expiresAt, // expiresAt
        price, // price (mid, 1e18)
        int192(0), // bid (ignored)
        int192(0) // ask (ignored)
      );
  }

  /// @notice Single report at the current block time, far from expiry/staleness bounds.
  function freshReport(bytes32 feedId, int192 price) internal view returns (bytes memory) {
    return buildReport(feedId, uint32(block.timestamp), uint32(block.timestamp + 1000), price);
  }

  function wrap(bytes memory a) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](1);
    arr[0] = a;
  }
}

contract DataStreamsRelayerV1Test_constructor is DataStreamsRelayerV1Test {
  function test_constructorRevertsWhenNoLegs() public {
    vm.expectRevert(NO_LEGS_ERROR);
    new DataStreamsRelayerV1(
      rateFeedId,
      "CELO/PHP",
      address(sortedOracles),
      address(verifierProxy),
      0,
      maxStaleness,
      new IDataStreamsRelayer.StreamLeg[](0)
    );
  }

  function test_constructorRevertsWhenTooManyLegs() public {
    vm.expectRevert(TOO_MANY_LEGS_ERROR);
    new DataStreamsRelayerV1(
      rateFeedId,
      "CELO/PHP",
      address(sortedOracles),
      address(verifierProxy),
      300,
      maxStaleness,
      new IDataStreamsRelayer.StreamLeg[](5)
    );
  }

  function test_constructorRevertsWhenInvalidFeedId() public {
    vm.expectRevert(INVALID_FEED_ID_ERROR);
    new DataStreamsRelayerV1(
      rateFeedId,
      "CELO/PHP",
      address(sortedOracles),
      address(verifierProxy),
      0,
      maxStaleness,
      new IDataStreamsRelayer.StreamLeg[](1) // feedId == bytes32(0)
    );
  }

  function test_constructorRevertsWhenSpreadZeroButMultipleLegs() public {
    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](2);
    legs[0] = IDataStreamsRelayer.StreamLeg(feedId0, false);
    legs[1] = IDataStreamsRelayer.StreamLeg(feedId1, false);
    vm.expectRevert(INVALID_MAX_TIMESTAMP_SPREAD_ERROR);
    new DataStreamsRelayerV1(rateFeedId, "X", address(sortedOracles), address(verifierProxy), 0, maxStaleness, legs);
  }

  function test_constructorRevertsWhenSpreadPositiveButSingleLeg() public {
    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](1);
    legs[0] = IDataStreamsRelayer.StreamLeg(feedId0, false);
    vm.expectRevert(INVALID_MAX_TIMESTAMP_SPREAD_ERROR);
    new DataStreamsRelayerV1(rateFeedId, "X", address(sortedOracles), address(verifierProxy), 300, maxStaleness, legs);
  }

  function test_constructorSetsImmutables() public {
    setUpRelayer(2, 300);
    assertEq(relayer.rateFeedId(), rateFeedId);
    assertEq(relayer.sortedOracles(), address(sortedOracles));
    assertEq(relayer.verifierProxy(), address(verifierProxy));
    assertEq(relayer.maxTimestampSpread(), 300);
    assertEq(relayer.maxStaleness(), maxStaleness);
    assertEq(relayer.rateFeedDescription(), "CELO/PHP");
    assertEq(relayer.lastObservationsTimestamp(), 0);

    IDataStreamsRelayer.StreamLeg[] memory legs = relayer.getLegs();
    assertEq(legs.length, 2);
    assertEq(legs[0].feedId, feedId0);
    assertEq(legs[0].invert, invert0);
    assertEq(legs[1].feedId, feedId1);
    assertEq(legs[1].invert, invert1);
  }
}

contract DataStreamsRelayerV1Test_relay is DataStreamsRelayerV1Test {
  function relay(bytes[] memory reports) internal {
    vm.prank(caller);
    relayer.relay(reports, "");
  }

  function median() internal returns (uint256 m) {
    (m, ) = sortedOracles.medianRate(rateFeedId);
  }

  // ----- decode + single-leg compose -----

  function test_relay_singleLeg_decodesAndComposes() public {
    setUpRelayer(1, 0);
    int192 price = 5e17; // 0.5 in 1e18
    relay(wrap(freshReport(feedId0, price)));
    // single leg, no invert: fixidity median = price * 1e6
    assertEq(median(), uint256(uint192(price)) * 1e6);
    assertEq(relayer.lastObservationsTimestamp(), block.timestamp);
  }

  function test_relay_singleLeg_emitsRelayed() public {
    setUpRelayer(1, 0);
    int192 price = 5e17;
    uint256 expectedRate = uint256(uint192(price)) * 1e6;
    vm.expectEmit(true, true, true, true);
    emit Relayed(rateFeedId, expectedRate, block.timestamp, caller);
    relay(wrap(freshReport(feedId0, price)));
  }

  function test_relay_singleLeg_invert() public {
    // invert leg0 by reconfiguring with an inverted single leg
    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](1);
    legs[0] = IDataStreamsRelayer.StreamLeg(feedId0, true);
    relayer = IDataStreamsRelayer(
      new DataStreamsRelayerV1(rateFeedId, "X", address(sortedOracles), address(verifierProxy), 0, maxStaleness, legs)
    );
    sortedOracles.addOracle(rateFeedId, address(relayer));

    int192 price = 4e18; // 4.0
    relay(wrap(freshReport(feedId0, price)));
    uint256 expected = intoUint256(ud(uint256(uint192(price))).inv()) * 1e6;
    assertEq(median(), expected);
  }

  // ----- multi-leg compose with invert flags (2/3/4) -----

  function _multiReports(uint256 legCount, int192[4] memory prices) internal view returns (bytes[] memory reports) {
    bytes32[4] memory ids = [feedId0, feedId1, feedId2, feedId3];
    reports = new bytes[](legCount);
    for (uint256 i = 0; i < legCount; i++) {
      reports[i] = freshReport(ids[i], prices[i]);
    }
  }

  function _expectedComposite(uint256 legCount, int192[4] memory prices) internal view returns (uint256) {
    bool[4] memory inverts = [invert0, invert1, invert2, invert3];
    UD60x18 acc = ud(1e18);
    for (uint256 i = 0; i < legCount; i++) {
      UD60x18 p = ud(uint256(uint192(prices[i])));
      if (inverts[i]) p = p.inv();
      acc = acc.mul(p);
    }
    return intoUint256(acc) * 1e6;
  }

  function test_relay_twoLegs_composeWithInvert() public {
    setUpRelayer(2, 300);
    int192[4] memory prices = [int192(5e17), int192(2e16), int192(0), int192(0)]; // CELO/USD=0.5, PHP/USD=0.02 inverted
    relay(_multiReports(2, prices));
    assertEq(median(), _expectedComposite(2, prices));
  }

  function test_relay_threeLegs_composeWithInvert() public {
    setUpRelayer(3, 300);
    int192[4] memory prices = [int192(5e17), int192(2e16), int192(11e17), int192(0)];
    relay(_multiReports(3, prices));
    assertEq(median(), _expectedComposite(3, prices));
  }

  function test_relay_fourLegs_composeWithInvert() public {
    setUpRelayer(4, 300);
    int192[4] memory prices = [int192(5e17), int192(2e16), int192(11e17), int192(13e17)];
    relay(_multiReports(4, prices));
    assertEq(median(), _expectedComposite(4, prices));
  }

  // ----- WrongFeedId binding -----

  function test_relay_revertsOnWrongFeedId() public {
    setUpRelayer(1, 0);
    bytes32 wrong = keccak256("WRONG/USD");
    vm.expectRevert(abi.encodeWithSignature("WrongFeedId(uint256,bytes32,bytes32)", uint256(0), feedId0, wrong));
    relay(wrap(freshReport(wrong, 5e17)));
  }

  function test_relay_revertsOnWrongFeedId_secondLeg() public {
    setUpRelayer(2, 300);
    bytes[] memory reports = new bytes[](2);
    reports[0] = freshReport(feedId0, 5e17);
    bytes32 wrong = keccak256("WRONG/USD");
    reports[1] = freshReport(wrong, 2e16);
    vm.expectRevert(abi.encodeWithSignature("WrongFeedId(uint256,bytes32,bytes32)", uint256(1), feedId1, wrong));
    relay(reports);
  }

  // ----- length / price / short report -----

  function test_relay_revertsOnLegCountMismatch() public {
    setUpRelayer(2, 300);
    vm.expectRevert(LEG_COUNT_MISMATCH_ERROR);
    relay(wrap(freshReport(feedId0, 5e17)));
  }

  function test_relay_revertsOnZeroPrice() public {
    setUpRelayer(1, 0);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relay(wrap(freshReport(feedId0, 0)));
  }

  function test_relay_revertsOnNegativePrice() public {
    setUpRelayer(1, 0);
    vm.expectRevert(INVALID_PRICE_ERROR);
    relay(wrap(freshReport(feedId0, -1)));
  }

  function test_relay_revertsOnShortReport() public {
    setUpRelayer(1, 0);
    vm.expectRevert(REPORT_TOO_SHORT_ERROR);
    relay(wrap(hex"deadbeef"));
  }

  // ----- staleness: expiresAt + maxStaleness boundaries -----

  function test_relay_expiresAt_boundary_accepts() public {
    setUpRelayer(1, 0);
    // block.timestamp == expiresAt is accepted (check is strict >)
    bytes memory r = buildReport(feedId0, uint32(block.timestamp), uint32(block.timestamp), 5e17);
    relay(wrap(r));
    assertEq(median(), uint256(uint192(int192(5e17))) * 1e6);
  }

  function test_relay_expiresAt_expired_reverts() public {
    setUpRelayer(1, 0);
    bytes memory r = buildReport(feedId0, uint32(block.timestamp), uint32(block.timestamp - 1), 5e17);
    vm.expectRevert(EXPIRED_SIGNATURE_ERROR);
    relay(wrap(r));
  }

  function test_relay_maxStaleness_boundary_accepts() public {
    setUpRelayer(1, 0);
    // block.timestamp - obsTs == maxStaleness is accepted (check is strict >)
    uint32 obsTs = uint32(block.timestamp - maxStaleness);
    bytes memory r = buildReport(feedId0, obsTs, uint32(block.timestamp + 1000), 5e17);
    relay(wrap(r));
    assertEq(relayer.lastObservationsTimestamp(), obsTs);
  }

  function test_relay_maxStaleness_tooStale_reverts() public {
    setUpRelayer(1, 0);
    uint32 obsTs = uint32(block.timestamp - maxStaleness - 1);
    bytes memory r = buildReport(feedId0, obsTs, uint32(block.timestamp + 1000), 5e17);
    vm.expectRevert(REPORT_TOO_STALE_ERROR);
    relay(wrap(r));
  }

  // ----- spread: == maxTimestampSpread accepts, +1 reverts -----

  function test_relay_spread_boundary_accepts() public {
    setUpRelayer(2, 300);
    bytes[] memory reports = new bytes[](2);
    uint32 newest = uint32(block.timestamp);
    uint32 oldest = uint32(block.timestamp - 300); // spread == 300
    reports[0] = buildReport(feedId0, newest, uint32(block.timestamp + 1000), 5e17);
    reports[1] = buildReport(feedId1, oldest, uint32(block.timestamp + 1000), 2e16);
    relay(reports);
    assertEq(relayer.lastObservationsTimestamp(), oldest); // composite = oldest
  }

  function test_relay_spread_tooHigh_reverts() public {
    setUpRelayer(2, 301); // staleness allows it, spread is the binding constraint
    bytes[] memory reports = new bytes[](2);
    uint32 newest = uint32(block.timestamp);
    uint32 oldest = uint32(block.timestamp - 302); // spread == 302 > 301
    reports[0] = buildReport(feedId0, newest, uint32(block.timestamp + 1000), 5e17);
    reports[1] = buildReport(feedId1, oldest, uint32(block.timestamp + 1000), 2e16);
    vm.expectRevert(TIMESTAMP_SPREAD_TOO_HIGH_ERROR);
    relay(reports);
  }

  // ----- replay: < reverts, == idempotent no-op, > accepts -----

  function test_relay_replay_olderReverts() public {
    setUpRelayer(1, 0);
    uint32 t0 = uint32(block.timestamp);
    relay(wrap(buildReport(feedId0, t0, uint32(block.timestamp + 1000), 5e17)));
    // older composite obs
    bytes memory older = buildReport(feedId0, t0 - 1, uint32(block.timestamp + 1000), 6e17);
    vm.expectRevert(STALE_REPORT_ERROR);
    relay(wrap(older));
  }

  function test_relay_replay_equalIsIdempotentNoop() public {
    setUpRelayer(1, 0);
    uint32 t0 = uint32(block.timestamp);
    relay(wrap(buildReport(feedId0, t0, uint32(block.timestamp + 1000), 5e17)));
    uint256 medianBefore = median();

    // Same observationsTimestamp, different price → must be a no-op, not a write.
    vm.expectEmit(false, false, false, true);
    emit ReportSkippedIdempotent(t0);
    vm.prank(caller);
    relayer.relay(wrap(buildReport(feedId0, t0, uint32(block.timestamp + 1000), 9e17)), "");

    assertEq(median(), medianBefore); // unchanged
    assertEq(relayer.lastObservationsTimestamp(), t0);
  }

  function test_relay_replay_newerAccepts() public {
    setUpRelayer(1, 0);
    uint32 t0 = uint32(block.timestamp);
    relay(wrap(buildReport(feedId0, t0, uint32(block.timestamp + 1000), 5e17)));

    vm.warp(block.timestamp + 10);
    uint32 t1 = uint32(block.timestamp);
    relay(wrap(buildReport(feedId0, t1, uint32(block.timestamp + 1000), 6e17)));

    assertEq(relayer.lastObservationsTimestamp(), t1);
    assertEq(median(), uint256(uint192(int192(6e17))) * 1e6);
  }
}
