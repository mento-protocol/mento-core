// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

/**
 * @notice Minimal interface for the Chainlink Data Streams VerifierProxy.
 * @dev On Celo mainnet s_feeManager() returns address(0), so parameterPayload
 *      should be empty bytes and no fee is required.
 *      Celo mainnet address: 0x57A97148C1fa50f35F0639f380077017D8893b6b
 *      Celo Alfajores address: 0xfa58eE98c9d56A3e6e903f300BE8C60Bf031808D
 */
interface IVerifierProxy {
  /**
   * @notice Verifies a single signed Data Streams report.
   * @param payload The signed report payload from the Data Streams API.
   * @param parameterPayload Fee parameter payload. Pass empty bytes on Celo (no FeeManager).
   * @return verifierResponse The ABI-encoded verified report.
   */
  function verify(
    bytes calldata payload,
    bytes calldata parameterPayload
  ) external payable returns (bytes memory verifierResponse);

  /**
   * @notice Verifies multiple signed reports in a single call.
   * @param payloads Array of signed report payloads, one per feed leg.
   * @param parameterPayload Fee parameter payload. Pass empty bytes on Celo (no FeeManager).
   * @return verifiedReports Array of ABI-encoded verified reports, aligned to payloads.
   */
  function verifyBulk(
    bytes[] calldata payloads,
    bytes calldata parameterPayload
  ) external payable returns (bytes[] memory verifiedReports);

  /**
   * @notice Returns the FeeManager address. Expected to be address(0) on Celo.
   * @dev Name mirrors Chainlink's deployed VerifierProxy ABI verbatim and must not be renamed.
   */
  // forge-lint: disable-next-line(mixed-case-function)
  // solhint-disable-next-line func-name-mixedcase
  function s_feeManager() external view returns (address);
}
