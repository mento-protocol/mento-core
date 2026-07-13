// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import { IPullOracleAdapter } from "contracts/interfaces/IPullOracleAdapter.sol";

/**
 * @notice Configurable IPullOracleAdapter mock for exercising the relayer/router seams the real
 *         ChainlinkDataStreamsAdapter cannot reach:
 *         - a nonzero verification fee (the payable forwarding chain router -> ingest -> relay ->
 *           adapter, incl. under/overfunding),
 *         - a misbehaving adapter returning misaligned arrays (AdapterResponseMismatch),
 *         - a zero price slipping through (the relayer's own InvalidPrice defense-in-depth).
 *         By default returns a fresh, aligned response: price 5e17 per leg, obsTs = now,
 *         expiry = now + 1000.
 */
contract MockPullOracleAdapter is IPullOracleAdapter {
  uint256 public fee;
  uint256 public lastReceivedValue;

  // Optional overrides for misbehavior tests.
  bool internal overrideResponse;
  uint256[] internal overridePrices;
  uint256[] internal overrideObs;
  uint256[] internal overrideExpiries;

  error FeeNotCovered(uint256 expected, uint256 got);

  function setFee(uint256 _fee) external {
    fee = _fee;
  }

  /// @notice Force verify() to return these exact arrays regardless of feedIds length.
  function setResponse(uint256[] calldata _prices, uint256[] calldata _obs, uint256[] calldata _expiries) external {
    overrideResponse = true;
    overridePrices = _prices;
    overrideObs = _obs;
    overrideExpiries = _expiries;
  }

  function verify(
    bytes32[] calldata feedIds,
    bytes calldata
  )
    external
    payable
    returns (uint256[] memory prices, uint256[] memory observationsTimestamps, uint256[] memory expiries)
  {
    // Interface invariant 5: exact fee match.
    if (msg.value != fee) revert FeeNotCovered(fee, msg.value);
    lastReceivedValue = msg.value;

    if (overrideResponse) {
      return (overridePrices, overrideObs, overrideExpiries);
    }

    uint256 length = feedIds.length;
    prices = new uint256[](length);
    observationsTimestamps = new uint256[](length);
    expiries = new uint256[](length);
    for (uint256 i = 0; i < length; i++) {
      prices[i] = 5e17;
      // solhint-disable-next-line not-rely-on-time
      observationsTimestamps[i] = block.timestamp;
      // solhint-disable-next-line not-rely-on-time
      expiries[i] = block.timestamp + 1000;
    }
  }

  function verificationFee(bytes calldata) external view returns (uint256) {
    return fee;
  }

  function provider() external pure returns (bytes32) {
    return bytes32("mock");
  }
}
