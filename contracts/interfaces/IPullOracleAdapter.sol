// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.13 <0.9;
pragma experimental ABIEncoderV2;

/**
 * @notice Provider-agnostic verification adapter for pull-oracle price updates.
 * @dev One implementation per provider (Chainlink Data Streams, Pyth, RedStone, ...). Each adapter
 *      verifies a provider-specific `updateData` blob and returns prices normalized to a common
 *      shape so the relayer stays provider-neutral. (Not to be confused with IOracleAdapter, the
 *      FPMM's read-side oracle adapter.)
 *
 *      Interface invariants every implementation MUST uphold:
 *      1. `updateData` MUST remain the last parameter of `verify` and callers MUST pass it via
 *         standard ABI encoding: its content is then the final calldata tail, which the RedStone
 *         adapter depends on (RedStone parses its payload marker from the END of msg.data).
 *      2. Revert on a non-positive or missing price — the interface returns uint256, so the caller
 *         can no longer observe a negative provider price (e.g. Pyth int64, Chainlink int192).
 *      3. Bind each returned price to the requested feedId (revert if the verified payload's feed
 *         does not match), so callers can trust positional alignment.
 *      4. Normalize timestamps to unix seconds and do NOT enforce staleness — freshness policy
 *         (staleness/expiry/spread gates) lives in the relayer, uniformly across providers.
 *      5. Enforce the fee deterministically: revert unless msg.value == verificationFee(updateData)
 *         (which is 0 for fee-less providers).
 */
interface IPullOracleAdapter {
  /**
   * @notice Verifies provider-specific `updateData` for `feedIds` and returns normalized prices.
   * @dev The blob is opaque to callers: Chainlink = abi.encode(bytes[] signedReports); Pyth =
   *      abi.encode(bytes[] hermesUpdates); RedStone = the signed payload (manual-usage encoding).
   * @param feedIds Provider feed identifiers, in leg order.
   * @param updateData The provider-specific update blob covering all requested feeds.
   * @return prices Mid/benchmark prices normalized to 1e18 fixed-point, aligned to `feedIds`.
   * @return observationsTimestamps Provider observation/publish times in unix seconds, aligned.
   * @return expiries Hard report expiry in unix seconds, aligned (type(uint32).max if none).
   */
  function verify(
    bytes32[] calldata feedIds,
    bytes calldata updateData
  )
    external
    payable
    returns (uint256[] memory prices, uint256[] memory observationsTimestamps, uint256[] memory expiries);

  /// @notice Native-token fee required to verify `updateData` (0 for fee-less providers).
  function verificationFee(bytes calldata updateData) external view returns (uint256);

  /**
   * @notice Provider identifier for off-chain resolution, e.g. bytes32("chainlink-data-streams"),
   *         bytes32("pyth"), bytes32("redstone").
   * @dev The SDK reads relayer.adapter().provider() to pick the matching data source.
   */
  function provider() external view returns (bytes32);
}
