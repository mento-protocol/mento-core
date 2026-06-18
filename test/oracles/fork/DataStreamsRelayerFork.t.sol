// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase, one-contract-per-file
pragma solidity ^0.8.19;

import { Test } from "mento-std/Test.sol";

import { MockVerifierProxy } from "test/utils/mocks/MockVerifierProxy.sol";
import { IDataStreamsRelayer } from "contracts/interfaces/IDataStreamsRelayer.sol";
import { DataStreamsRelayerV1 } from "contracts/oracles/DataStreamsRelayerV1.sol";
import { MedianDeltaBreakerV2 } from "contracts/oracles/breakers/MedianDeltaBreakerV2.sol";

interface ISortedOracles {
  function initialize(uint256) external;

  function addOracle(address, address) external;

  function setTokenReportExpiry(address, uint256) external;

  function medianRate(address) external returns (uint256, uint256);

  function owner() external view returns (address);
}

/**
 * @notice Shared report-blob builder for the Data Streams fork harness.
 * @dev Builds a V3-shaped report. The relayer decoder reads only
 *      feedId / observationsTimestamp / expiresAt / price; trailing fields are ignored.
 *
 * @dev NAMING: these contracts are deliberately NOT named "*ForkTest". The default Foundry
 *      profile sets `no_match_contract = "ForkTest"`, which would exclude them; the goal runs
 *      this file via `--match-path 'test/oracles/fork/*'` on the default profile, so the
 *      negative-path tests must be runnable there. The live tests self-skip without fixtures.
 */
abstract contract DataStreamsForkBase is Test {
  function _buildReport(
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

  function _wrap(bytes memory a) internal pure returns (bytes[] memory arr) {
    arr = new bytes[](1);
    arr[0] = a;
  }
}

/**
 * @title DataStreamsRelayerNegativePath
 * @notice Negative-path tests that run unconditionally against a mock VerifierProxy:
 *         a tampered signed-report byte, an expired report (warped past expiresAt), and a
 *         wrong feedId. These assert the relayer rejects bad input regardless of the source,
 *         and do NOT depend on the live verifier or any captured fixture.
 */
contract DataStreamsRelayerNegativePath is DataStreamsForkBase {
  bytes constant EXPIRED_SIGNATURE_ERROR = abi.encodeWithSignature("ExpiredSignature()");

  ISortedOracles sortedOracles;
  address rateFeedId = makeAddr("CELO/USD");
  bytes32 feedId0 = keccak256("CELO/USD");
  uint256 maxStaleness = 600;

  function setUp() public {
    vm.warp(100_000);
    sortedOracles = ISortedOracles(deployCode("SortedOracles", abi.encode(true)));
    sortedOracles.initialize(3600);
    sortedOracles.setTokenReportExpiry(rateFeedId, 3600);
  }

  function _singleLeg(bytes32 feedId) internal pure returns (IDataStreamsRelayer.StreamLeg[] memory legs) {
    legs = new IDataStreamsRelayer.StreamLeg[](1);
    legs[0] = IDataStreamsRelayer.StreamLeg(feedId, false);
  }

  function _deployRelayer(address verifier) internal returns (DataStreamsRelayerV1 relayer) {
    relayer = new DataStreamsRelayerV1(
      rateFeedId,
      "CELO/USD",
      address(sortedOracles),
      verifier,
      0,
      maxStaleness,
      _singleLeg(feedId0)
    );
    sortedOracles.addOracle(rateFeedId, address(relayer));
  }

  // ---- tampered signed-report byte (strict mock models DON signature auth) ----

  function test_strictMock_acceptsAuthenticPayload() public {
    MockVerifierProxy verifier = new MockVerifierProxy();
    verifier.setStrict(true);
    DataStreamsRelayerV1 relayer = _deployRelayer(address(verifier));

    int192 price = 5e17;
    bytes memory report = _buildReport(feedId0, uint32(block.timestamp), uint32(block.timestamp + 1000), price);
    bytes memory signed = abi.encode("DON-SIGNED-ENVELOPE", report); // stand-in for the signed blob
    verifier.register(signed, report);

    relayer.relay(_wrap(signed), "");
    (uint256 median, ) = sortedOracles.medianRate(rateFeedId);
    assertEq(median, uint256(uint192(price)) * 1e6);
  }

  function test_tamperedSignatureByte_reverts() public {
    MockVerifierProxy verifier = new MockVerifierProxy();
    verifier.setStrict(true);
    DataStreamsRelayerV1 relayer = _deployRelayer(address(verifier));

    bytes memory report = _buildReport(feedId0, uint32(block.timestamp), uint32(block.timestamp + 1000), 5e17);
    bytes memory signed = abi.encode("DON-SIGNED-ENVELOPE", report);
    verifier.register(signed, report);

    // Flip a single byte of the signed envelope: the verifier no longer recognizes it.
    bytes memory tampered = bytes.concat(signed);
    tampered[tampered.length - 1] = tampered[tampered.length - 1] ^ bytes1(0x01);

    vm.expectRevert(MockVerifierProxy.VerificationFailed.selector);
    relayer.relay(_wrap(tampered), "");
  }

  // ---- expired report (warp past expiresAt) ----

  function test_expiredReport_reverts() public {
    MockVerifierProxy verifier = new MockVerifierProxy(); // echo mode: payload == verified report
    DataStreamsRelayerV1 relayer = _deployRelayer(address(verifier));

    uint32 expiresAt = uint32(block.timestamp + 100);
    bytes memory report = _buildReport(feedId0, uint32(block.timestamp), expiresAt, 5e17);

    vm.warp(uint256(expiresAt) + 1); // now strictly past expiresAt
    vm.expectRevert(EXPIRED_SIGNATURE_ERROR);
    relayer.relay(_wrap(report), "");
  }

  // ---- wrong feedId ----

  function test_wrongFeedId_reverts() public {
    MockVerifierProxy verifier = new MockVerifierProxy();
    DataStreamsRelayerV1 relayer = _deployRelayer(address(verifier));

    bytes32 wrong = keccak256("WRONG/USD");
    bytes memory report = _buildReport(wrong, uint32(block.timestamp), uint32(block.timestamp + 1000), 5e17);

    vm.expectRevert(abi.encodeWithSignature("WrongFeedId(uint256,bytes32,bytes32)", uint256(0), feedId0, wrong));
    relayer.relay(_wrap(report), "");
  }
}

/**
 * @title DataStreamsRelayerLiveFixtures
 * @notice End-to-end test against the REAL Chainlink Data Streams VerifierProxy on a Celo fork,
 *         using captured DON-signed report blobs from `fixtures/datastreams/reports.json`.
 * @dev GATED: skips (never passes, never deleted) unless ALL of these are present:
 *        - env DS_FORK_RPC_URL (a Celo archive RPC),
 *        - env DS_VERIFIER_PROXY (B1) and DS_SORTED_ORACLES (B5),
 *        - the committed fixture file `fixtures/datastreams/reports.json` (captured per the README).
 *      We cannot synthesize DON signatures, so without real fixtures there is nothing valid to
 *      submit — the only honest outcome is to skip. See fixtures/datastreams/README.md.
 */
contract DataStreamsRelayerLiveFixtures is DataStreamsForkBase {
  string constant FIXTURE_PATH = "fixtures/datastreams/reports.json";

  /// @notice JSON shape of a single leg. Keys decode into these fields in ALPHABETICAL order:
  ///         feedId, invert, signedReport — keep the JSON keys named exactly so.
  struct FixtureLeg {
    bytes32 feedId;
    bool invert;
    bytes signedReport;
  }

  function test_liveRelay_writesMedianAndEvaluatesBreaker() public {
    string memory rpc = vm.envOr("DS_FORK_RPC_URL", string(""));
    address verifierProxy = vm.envOr("DS_VERIFIER_PROXY", address(0));
    address sortedOracles = vm.envOr("DS_SORTED_ORACLES", address(0));
    bool haveFixture = vm.isFile(FIXTURE_PATH);

    if (bytes(rpc).length == 0 || verifierProxy == address(0) || sortedOracles == address(0) || !haveFixture) {
      vm.skip(
        true,
        "live VerifierProxy fork test skipped: fixtures absent / VERIFIER_PROXY (or RPC/SortedOracles) unset"
      );
      return;
    }

    // ---- load fixtures ----
    string memory json = vm.readFile(FIXTURE_PATH);
    uint256 pinBlock = vm.parseJsonUint(json, ".pinBlock");
    address rateFeedId = vm.parseJsonAddress(json, ".rateFeedId");
    string memory description = vm.parseJsonString(json, ".description");
    uint256 maxTimestampSpread = vm.parseJsonUint(json, ".maxTimestampSpread");
    uint256 maxStaleness = vm.parseJsonUint(json, ".maxStaleness");
    FixtureLeg[] memory fixtureLegs = abi.decode(vm.parseJson(json, ".legs"), (FixtureLeg[]));

    // ---- pin the fork to a block inside the report validity window ----
    vm.createSelectFork(rpc, pinBlock);

    IDataStreamsRelayer.StreamLeg[] memory legs = new IDataStreamsRelayer.StreamLeg[](fixtureLegs.length);
    bytes[] memory signedReports = new bytes[](fixtureLegs.length);
    for (uint256 i = 0; i < fixtureLegs.length; i++) {
      legs[i] = IDataStreamsRelayer.StreamLeg(fixtureLegs[i].feedId, fixtureLegs[i].invert);
      signedReports[i] = fixtureLegs[i].signedReport;
    }

    // ---- deploy a relayer pointed at the REAL VerifierProxy + SortedOracles ----
    DataStreamsRelayerV1 relayer = new DataStreamsRelayerV1(
      rateFeedId,
      description,
      sortedOracles,
      verifierProxy,
      maxTimestampSpread,
      maxStaleness,
      legs
    );

    // authorize the relayer as a reporter for the feed
    address sortedOraclesOwner = ISortedOracles(sortedOracles).owner();
    vm.prank(sortedOraclesOwner);
    ISortedOracles(sortedOracles).addOracle(rateFeedId, address(relayer));

    // ---- relay() runs the REAL verification, then writes to SortedOracles ----
    relayer.relay(signedReports, "");
    (uint256 median, ) = ISortedOracles(sortedOracles).medianRate(rateFeedId);
    assertGt(median, 0, "median should be written after a verified relay");

    // ---- breaker evaluates on the freshly written median ----
    MedianDeltaBreakerV2 breaker = new MedianDeltaBreakerV2(
      300, // cooldown > 0
      sortedOracles,
      address(this), // breakerBox = this test, so we can drive shouldTrigger directly
      5e21, // baseJump 0.5%
      5555555555555555555, // slewPerSecond 2%/h
      5e22, // maxJump 5%
      address(this)
    );
    assertFalse(breaker.shouldTrigger(rateFeedId), "first observation seeds, must not trip");
    assertFalse(breaker.shouldTrigger(rateFeedId), "same median in-block must not trip");
  }
}
