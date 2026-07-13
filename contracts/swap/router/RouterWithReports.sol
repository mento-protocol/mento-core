// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
// solhint-disable immutable-vars-naming

import { Router } from "./Router.sol";
import { IFPMM } from "../../interfaces/IFPMM.sol";
import { IPullOracleRelayerFactory } from "contracts/interfaces/IPullOracleRelayerFactory.sol";
import { IPullOracleRelayer } from "contracts/interfaces/IPullOracleRelayer.sol";
import { IPullOracleAdapter } from "contracts/interfaces/IPullOracleAdapter.sol";

/// @title RouterWithReports
/// @author Mento Labs
/// @notice Router variant that supports just-in-time pull-oracle verification.
/// @dev Extends the base {Router} with `swapExactTokensForTokensWithReports`, which ingests a
///      fresh, provider-signed price update for each hop BEFORE the existing swap body reads the
///      oracle. This is the keeperless verify-on-swap path: `ingest` -> relayer `relay()` ->
///      adapter verify -> `SortedOracles.report()` (which also evaluates breakers) runs as a
///      state-changing pre-step, after which the existing `view` rate read returns the
///      freshly-written rate. Provider specifics (Chainlink Data Streams, Pyth, RedStone, ...)
///      live behind the relayer's IPullOracleAdapter.
///
///      Rationale for a Router-native function (not a Multicall3 periphery): the Router is
///      {ERC2771Context} and pulls input tokens from `_msgSender()`, so routing the swap through
///      a periphery contract would break the token pull (and a shared approval to a generic
///      multicall is a drainable footgun). See the migration plan §2.7.5.
///
///      The Router is not upgradeable; this is deployed as a fresh Router that the dapp/integrators
///      repoint to. `Factory.ingest` remains the standalone permissionless entry point for recovery.
contract RouterWithReports is Router {
  /// @notice The trusted PullOracleRelayerFactory that resolves `rateFeedId -> relayer` and verifies updates.
  /// @dev Immutable and constructor-set, never caller-supplied, so updates can only be routed to the
  ///      governance-deployed relayer set (an attacker cannot point ingestion at a malicious factory).
  address public immutable pullOracleRelayerFactory;

  /// @notice Thrown when the per-hop updateData array length does not match the routes length.
  error ReportsLengthMismatch();

  /// @notice Thrown when a `*WithReports` function is called but no PullOracleRelayerFactory is configured.
  error PullOracleRelayerFactoryNotSet();

  /// @notice Thrown when msg.value does not exactly cover the sum of per-hop verification fees.
  error FeeMismatch();

  /**
   * @param _forwarder Trusted ERC-2771 forwarder (or address(0)).
   * @param _factoryRegistry The FactoryRegistry used to validate pool factories.
   * @param _factory The default pool factory.
   * @param _pullOracleRelayerFactory The PullOracleRelayerFactory whose `ingest` is called per hop.
   */
  constructor(
    address _forwarder,
    address _factoryRegistry,
    address _factory,
    address _pullOracleRelayerFactory
  ) Router(_forwarder, _factoryRegistry, _factory) {
    pullOracleRelayerFactory = _pullOracleRelayerFactory;
  }

  /**
   * @notice Same as {Router-swapExactTokensForTokens}, but first verifies and writes a fresh
   *         pull-oracle update for each hop so the swap reads a just-verified rate.
   * @dev Ordering is load-bearing: `_ingestUpdates` runs BEFORE `getAmountsOut` (which reads the
   *      oracle and reverts on a stale rate). Because `ingest -> report -> checkAndSetBreakers`
   *      updates the trading mode before the read, a depeg report trips the breaker and this same
   *      swap then reverts. `amountOutMin` still bounds user loss.
   *
   *      Payable: msg.value must EXACTLY cover the sum of per-hop verification fees (queried from
   *      each relayer's adapter). No refunds are issued — an exact match is required so no native
   *      transfer back to the caller happens mid-swap. Fees are 0 for fee-less providers
   *      (Chainlink-on-Celo, RedStone), so the common case sends no value at all.
   * @param amountIn The exact input amount.
   * @param amountOutMin The minimum acceptable output (slippage bound).
   * @param routes The swap route (one entry per hop).
   * @param to The recipient of the final output.
   * @param deadline The transaction deadline.
   * @param updateDataPerHop Provider update blobs aligned to `routes` (entry `i` -> hop `i`). An
   *        empty entry skips ingestion for that hop (e.g. a hop on a push pair, or a feed already
   *        made fresh by an earlier hop in the same tx).
   * @return amounts The amounts out for each hop (same shape as the base function).
   */
  function swapExactTokensForTokensWithReports(
    uint256 amountIn,
    uint256 amountOutMin,
    Route[] calldata routes,
    address to,
    uint256 deadline,
    bytes[] calldata updateDataPerHop
  ) external payable ensure(deadline) returns (uint256[] memory amounts) {
    // STATE pre-step: verify + write fresh updates before any oracle read.
    _ingestUpdates(routes, updateDataPerHop);

    // ---- existing swapExactTokensForTokens body, verbatim ----
    amounts = getAmountsOut(amountIn, routes);
    if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
    _safeTransferFrom(
      routes[0].from,
      _msgSender(),
      poolFor(routes[0].from, routes[0].to, routes[0].factory),
      amounts[0]
    );
    _swap(amounts, routes, to);
  }

  /**
   * @notice Ingests one provider update blob per hop, routing each to the relayer for that hop's
   *         pool `referenceRateFeedID` via the trusted PullOracleRelayerFactory.
   * @dev A shared feed across hops makes the second `ingest` an idempotent no-op (handled in the
   *      relayer). Hops with an empty update blob are skipped. Each hop's verification fee is
   *      queried from the relayer's adapter and forwarded exactly; the running total must consume
   *      msg.value exactly (checked math reverts on underfunding, FeeMismatch on overfunding).
   */
  function _ingestUpdates(Route[] calldata routes, bytes[] calldata updateDataPerHop) internal {
    if (updateDataPerHop.length != routes.length) revert ReportsLengthMismatch();

    address factory = pullOracleRelayerFactory;
    if (factory == address(0)) revert PullOracleRelayerFactoryNotSet();

    uint256 remaining = msg.value;
    uint256 length = routes.length;
    for (uint256 i = 0; i < length; i++) {
      if (updateDataPerHop[i].length == 0) {
        continue; // hop carries no update (push pair, or feed already fresh this tx)
      }
      // Resolve the same pool the swap will use, then its reference rate feed.
      address pool = poolFor(routes[i].from, routes[i].to, routes[i].factory);
      address rateFeedId = IFPMM(pool).referenceRateFeedID();

      // Query the hop's verification fee from the relayer's adapter (0 for fee-less providers).
      // A missing relayer is left to ingest(), which reverts NoRelayerForRateFeedId.
      uint256 fee = 0;
      address relayer = IPullOracleRelayerFactory(factory).getRelayer(rateFeedId);
      if (relayer != address(0)) {
        fee = IPullOracleAdapter(IPullOracleRelayer(relayer).adapter()).verificationFee(updateDataPerHop[i]);
      }

      remaining -= fee; // checked math: reverts if msg.value underfunds the fees
      IPullOracleRelayerFactory(factory).ingest{ value: fee }(rateFeedId, updateDataPerHop[i]);
    }
    if (remaining != 0) revert FeeMismatch();
  }
}
