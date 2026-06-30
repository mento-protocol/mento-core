// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase, one-contract-per-file
pragma solidity ^0.8.19;

import { Test } from "mento-std/Test.sol";

import { MockVerifierProxy } from "test/utils/mocks/MockVerifierProxy.sol";
import { IDataStreamsRelayer } from "contracts/interfaces/IDataStreamsRelayer.sol";
import { DataStreamsRelayerV1 } from "contracts/oracles/DataStreamsRelayerV1.sol";

interface ISortedOracles {
  function initialize(uint256) external;

  function addOracle(address, address) external;

  function setTokenReportExpiry(address, uint256) external;

  function medianRate(address) external returns (uint256, uint256);
}

/**
 * @notice Shared report-blob builder for the Data Streams negative-path tests.
 * @dev Builds a V3-shaped report. The relayer decoder reads only
 *      feedId / observationsTimestamp / expiresAt / price; trailing fields are ignored.
 *
 * @dev NAMING: these contracts are deliberately NOT named "*ForkTest". The default Foundry
 *      profile sets `no_match_contract = "ForkTest"`, which would exclude them; this file runs
 *      via `--match-path 'test/oracles/fork/*'` on the default profile, so the negative-path
 *      tests must be runnable there.
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
