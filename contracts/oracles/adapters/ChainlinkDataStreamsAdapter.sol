// SPDX-License-Identifier: BUSL-1.1
// solhint-disable immutable-vars-naming
pragma solidity 0.8.19;

import { IPullOracleAdapter } from "../../interfaces/IPullOracleAdapter.sol";
import { IVerifierProxy } from "../../interfaces/IVerifierProxy.sol";

/**
 * @title ChainlinkDataStreamsAdapter
 * @notice IPullOracleAdapter implementation for Chainlink Data Streams.
 * @dev Verifies DON-signed report blobs via the Chainlink VerifierProxy and decodes the verified
 *      report structs into the normalized (price, observationsTimestamp, expiry) shape. All
 *      Chainlink specifics — the VerifierProxy dependency, report schema layouts, feedId schema
 *      prefixes — are contained here; the relayer only sees the IPullOracleAdapter interface.
 *
 *      `updateData` encoding for this adapter: abi.encode(bytes[] signedReports), one signed report
 *      per requested feedId, in feedId order. The verification fee is 0: Celo's VerifierProxy has
 *      no FeeManager (s_feeManager() == address(0)), so verification is free and the empty
 *      parameterPayload is used. If a FeeManager is ever configured, deploy a new adapter version.
 */
contract ChainlinkDataStreamsAdapter is IPullOracleAdapter {
  /// @notice The Chainlink Data Streams VerifierProxy used to authenticate reports.
  address public immutable verifierProxy;

  /// @notice Used when msg.value is non-zero (Chainlink verification is free on Celo).
  error UnexpectedFee();

  /// @notice Used when the decoded signedReports length does not match the requested feedIds length.
  error LegCountMismatch();

  /**
   * @notice Used when a verified report's feedId does not match the feedId requested
   * for that position.
   */
  error WrongFeedId(uint256 index, bytes32 expected, bytes32 got);

  /// @notice Used when a negative or zero price is decoded from a report.
  error InvalidPrice();

  /// @notice Used when the decoded report payload is shorter than the minimum expected length.
  error ReportTooShort();

  /// @notice Used when a report's schema version (feedId prefix) is not one the adapter can decode.
  error UnsupportedSchema(uint16 version);

  /**
   * @param _verifierProxy Address of the Chainlink Data Streams VerifierProxy.
   */
  constructor(address _verifierProxy) {
    verifierProxy = _verifierProxy;
  }

  /// @inheritdoc IPullOracleAdapter
  function verify(
    bytes32[] calldata feedIds,
    bytes calldata updateData
  )
    external
    payable
    returns (uint256[] memory prices, uint256[] memory observationsTimestamps, uint256[] memory expiries)
  {
    if (msg.value != 0) revert UnexpectedFee();

    bytes[] memory signedReports = abi.decode(updateData, (bytes[]));
    if (signedReports.length != feedIds.length) revert LegCountMismatch();

    // Empty parameterPayload: no FeeManager on Celo.
    bytes[] memory verifiedReports = IVerifierProxy(verifierProxy).verifyBulk(signedReports, "");

    uint256 length = feedIds.length;
    prices = new uint256[](length);
    observationsTimestamps = new uint256[](length);
    expiries = new uint256[](length);

    for (uint256 i = 0; i < length; i++) {
      (bytes32 reportFeedId, uint32 obsTs, uint32 expiresAt, int192 price) = decodeReport(verifiedReports[i]);
      if (reportFeedId != feedIds[i]) revert WrongFeedId(i, feedIds[i], reportFeedId);
      if (price <= 0) revert InvalidPrice();

      prices[i] = uint256(uint192(price));
      observationsTimestamps[i] = obsTs;
      expiries[i] = expiresAt;
    }
  }

  /// @inheritdoc IPullOracleAdapter
  function verificationFee(bytes calldata) external pure returns (uint256) {
    return 0;
  }

  /// @inheritdoc IPullOracleAdapter
  function provider() external pure returns (bytes32) {
    return bytes32("chainlink-data-streams");
  }

  /**
   * @notice Decodes the fields needed by the relayer from an ABI-encoded verified report.
   * @dev The verified report returned by VerifierProxy.verifyBulk() is an ABI-encoded struct. The
   * first six 32-byte slots are common across the schemas the adapter accepts:
   *
   *   slot 0 (bytes   0-31): bytes32 feedId
   *   slot 1 (bytes  32-63): uint32  validFromTimestamp
   *   slot 2 (bytes  64-95): uint32  observationsTimestamp
   *   slot 3 (bytes 96-127): uint192 nativeFee
   *   slot 4 (bytes 128-159): uint192 linkFee
   *   slot 5 (bytes 160-191): uint32  expiresAt
   *
   * The price sits at a schema-dependent slot (the feedId's first two bytes are the schema version):
   *   V3 (0x0003, Crypto Advanced): price    at slot 6 (offset 224)
   *   V8 (0x0008, RWA/forex):       midPrice at slot 7 (offset 256) — V8 inserts a uint64
   *                                 lastUpdateTimestamp at slot 6, shifting the price down one slot.
   *
   * Any other schema reverts UnsupportedSchema rather than reading a wrong slot (e.g. V5 slot 6 is a
   * rate, V9 is navPerShare) and silently writing a corrupted price. Extend the allowlist deliberately
   * if a new stream type is added.
   *
   * Confirmed against reality: an eth_call to the live Celo mainnet VerifierProxy 2.0.0
   * (0x57A97148C1fa50f35F0639f380077017D8893b6b, s_feeManager() == address(0)) with a real forex
   * report returned the bare report struct (slot 0 == feedId, not an envelope), decoding to the
   * expected price/timestamps at these offsets. So verify()/verifyBulk() return the report struct
   * directly.
   * @param report The ABI-encoded verified report bytes.
   * @return feedId The Data Streams feedId (bytes32 stream identifier).
   * @return observationsTimestamp When the DON observed the price (unix seconds).
   * @return expiresAt Hard DON-signed expiry (unix seconds).
   * @return price Mid price in 1e18 fixed-point (int192).
   */
  function decodeReport(
    bytes memory report
  ) internal pure returns (bytes32 feedId, uint32 observationsTimestamp, uint32 expiresAt, int192 price) {
    // Must at least hold the common prefix + the slot-6 price (the V3 minimum).
    if (report.length < 224) revert ReportTooShort();
    // solhint-disable-next-line no-inline-assembly
    assembly {
      feedId := mload(add(report, 32))
    }

    uint16 schemaVersion = uint16(bytes2(feedId));
    uint256 priceOffset;
    if (schemaVersion == 3) {
      priceOffset = 224; // slot 6
    } else if (schemaVersion == 8) {
      if (report.length < 256) revert ReportTooShort(); // V8 price is at slot 7
      priceOffset = 256;
    } else {
      revert UnsupportedSchema(schemaVersion);
    }

    // solhint-disable-next-line no-inline-assembly
    assembly {
      observationsTimestamp := mload(add(report, 96))
      expiresAt := mload(add(report, 192))
      price := mload(add(report, priceOffset))
    }
  }
}
