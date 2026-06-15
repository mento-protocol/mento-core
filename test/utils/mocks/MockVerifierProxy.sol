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

  error VerificationFailed();

  function setShouldRevert(bool _shouldRevert) external {
    shouldRevert = _shouldRevert;
  }

  function verify(
    bytes calldata payload,
    bytes calldata /* parameterPayload */
  ) external payable returns (bytes memory verifierResponse) {
    if (shouldRevert) revert VerificationFailed();
    return payload;
  }

  function verifyBulk(
    bytes[] calldata payloads,
    bytes calldata /* parameterPayload */
  ) external payable returns (bytes[] memory verifiedReports) {
    if (shouldRevert) revert VerificationFailed();
    verifiedReports = new bytes[](payloads.length);
    for (uint256 i = 0; i < payloads.length; i++) {
      verifiedReports[i] = payloads[i];
    }
    return verifiedReports;
  }

  function s_feeManager() external pure returns (address) {
    return address(0);
  }
}
