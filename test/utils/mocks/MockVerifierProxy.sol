// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import { IVerifierProxy } from "contracts/interfaces/IVerifierProxy.sol";

/**
 * @title MockVerifierProxy
 * @notice A mock Chainlink Data Streams VerifierProxy for unit tests.
 * @dev In production the VerifierProxy authenticates DON signatures and returns the decoded
 *      report payload. For unit tests we treat the "signed report" as already being the
 *      ABI-encoded verified report and echo it back, so tests can craft report fields directly.
 *      This mirrors the real verify/verifyBulk return shape (the inner report bytes) without
 *      needing real signatures. `s_feeManager()` returns address(0), matching Celo (no fee).
 */
contract MockVerifierProxy is IVerifierProxy {
  /// @notice When true, verify/verifyBulk revert to simulate a failed verification.
  bool public shouldRevert;

  /// @notice When true, only registered signed payloads verify; anything else reverts.
  /// @dev Models DON signature authentication: the verifier returns the inner report for an
  ///      authentic signed envelope and rejects any tampering. Default false preserves the
  ///      plain echo behavior that the unit tests rely on.
  bool public strict;

  mapping(bytes32 => bool) private registered;
  mapping(bytes32 => bytes) private reportForPayload;

  error VerificationFailed();

  function setShouldRevert(bool _shouldRevert) external {
    shouldRevert = _shouldRevert;
  }

  function setStrict(bool _strict) external {
    strict = _strict;
  }

  /**
   * @notice Registers an authentic signed payload and the verified report it resolves to.
   * @dev In strict mode, verify(payload) returns `verifiedReport` only for this exact
   *      `signedPayload`; flipping any byte of the payload makes it unregistered and reverts.
   */
  function register(bytes calldata signedPayload, bytes calldata verifiedReport) external {
    bytes32 key = keccak256(signedPayload);
    registered[key] = true;
    reportForPayload[key] = verifiedReport;
  }

  function verify(
    bytes calldata payload,
    bytes calldata /* parameterPayload */
  ) external payable returns (bytes memory verifierResponse) {
    if (shouldRevert) revert VerificationFailed();
    return _resolve(payload);
  }

  function verifyBulk(
    bytes[] calldata payloads,
    bytes calldata /* parameterPayload */
  ) external payable returns (bytes[] memory verifiedReports) {
    if (shouldRevert) revert VerificationFailed();
    verifiedReports = new bytes[](payloads.length);
    for (uint256 i = 0; i < payloads.length; i++) {
      verifiedReports[i] = _resolve(payloads[i]);
    }
    return verifiedReports;
  }

  function s_feeManager() external pure returns (address) {
    return address(0);
  }

  /// @dev In strict mode resolves a registered payload to its verified report (reverting on a
  ///      tampered/unknown payload); otherwise echoes the payload back as the verified report.
  function _resolve(bytes calldata payload) internal view returns (bytes memory) {
    if (!strict) {
      return payload;
    }
    bytes32 key = keccak256(payload);
    if (!registered[key]) revert VerificationFailed();
    return reportForPayload[key];
  }
}
