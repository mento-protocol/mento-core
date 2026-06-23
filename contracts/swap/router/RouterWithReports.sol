// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
// solhint-disable immutable-vars-naming

import { Router } from "./Router.sol";
import { IFPMM } from "../../interfaces/IFPMM.sol";
import { IDataStreamsRelayerFactory } from "contracts/interfaces/IDataStreamsRelayerFactory.sol";

/// @title RouterWithReports
/// @author Mento Labs
/// @notice Router variant that supports just-in-time Chainlink Data Streams verification.
/// @dev Extends the base {Router} with `swapExactTokensForTokensWithReports`, which ingests a
///      fresh, DON-signed report for each hop BEFORE the existing swap body reads the oracle.
///      This is the keeperless verify-on-swap path: `ingest` -> relayer `relay()` -> verify ->
///      `SortedOracles.report()` (which also evaluates breakers) runs as a state-changing
///      pre-step, after which the existing `view` rate read returns the freshly-written rate.
///
///      Rationale for a Router-native function (not a Multicall3 periphery): the Router is
///      {ERC2771Context} and pulls input tokens from `_msgSender()`, so routing the swap through
///      a periphery contract would break the token pull (and a shared approval to a generic
///      multicall is a drainable footgun). See the migration plan §2.7.5.
///
///      The Router is not upgradeable; this is deployed as a fresh Router that the dapp/integrators
///      repoint to. `Factory.ingest` remains the standalone permissionless entry point for recovery.
contract RouterWithReports is Router {
  /// @notice The trusted DataStreamsRelayerFactory that resolves `rateFeedId -> relayer` and verifies reports.
  /// @dev Immutable and constructor-set, never caller-supplied, so reports can only be routed to the
  ///      governance-deployed relayer set (an attacker cannot point ingestion at a malicious factory).
  address public immutable dataStreamsRelayerFactory;

  /// @notice Thrown when the per-hop reports array length does not match the routes length.
  error ReportsLengthMismatch();

  /// @notice Thrown when a `*WithReports` function is called but no DataStreamsRelayerFactory is configured.
  error DataStreamsRelayerFactoryNotSet();

  /**
   * @param _forwarder Trusted ERC-2771 forwarder (or address(0)).
   * @param _factoryRegistry The FactoryRegistry used to validate pool factories.
   * @param _factory The default pool factory.
   * @param _dataStreamsRelayerFactory The DataStreamsRelayerFactory whose `ingest` is called per hop.
   */
  constructor(
    address _forwarder,
    address _factoryRegistry,
    address _factory,
    address _dataStreamsRelayerFactory
  ) Router(_forwarder, _factoryRegistry, _factory) {
    dataStreamsRelayerFactory = _dataStreamsRelayerFactory;
  }

  /**
   * @notice Same as {Router-swapExactTokensForTokens}, but first verifies and writes a fresh Data
   *         Streams report for each hop so the swap reads a just-verified rate.
   * @dev Ordering is load-bearing: `_ingestReports` runs BEFORE `getAmountsOut` (which reads the
   *      oracle and reverts on a stale rate). Because `ingest -> report -> checkAndSetBreakers`
   *      updates the trading mode before the read, a depeg report trips the breaker and this same
   *      swap then reverts. `amountOutMin` still bounds user loss.
   * @param amountIn The exact input amount.
   * @param amountOutMin The minimum acceptable output (slippage bound).
   * @param routes The swap route (one entry per hop).
   * @param to The recipient of the final output.
   * @param deadline The transaction deadline.
   * @param signedReportsPerHop Signed reports aligned to `routes` (entry `i` -> hop `i`). An empty
   *        entry skips ingestion for that hop (e.g. a hop on a push pair, or a feed already made
   *        fresh by an earlier hop in the same tx).
   * @return amounts The amounts out for each hop (same shape as the base function).
   */
  function swapExactTokensForTokensWithReports(
    uint256 amountIn,
    uint256 amountOutMin,
    Route[] calldata routes,
    address to,
    uint256 deadline,
    bytes[][] calldata signedReportsPerHop
  ) external ensure(deadline) returns (uint256[] memory amounts) {
    // STATE pre-step: verify + write fresh reports before any oracle read.
    _ingestReports(routes, signedReportsPerHop);

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
   * @notice Ingests one signed report bundle per hop, routing each to the relayer for that hop's
   *         pool `referenceRateFeedID` via the trusted DataStreamsRelayerFactory.
   * @dev A shared feed across hops makes the second `ingest` an idempotent no-op (handled in the
   *      relayer). Hops with an empty report bundle are skipped.
   */
  function _ingestReports(Route[] calldata routes, bytes[][] calldata signedReportsPerHop) internal {
    if (signedReportsPerHop.length != routes.length) revert ReportsLengthMismatch();

    address factory = dataStreamsRelayerFactory;
    if (factory == address(0)) revert DataStreamsRelayerFactoryNotSet();

    uint256 length = routes.length;
    for (uint256 i = 0; i < length; i++) {
      if (signedReportsPerHop[i].length == 0) {
        continue; // hop carries no report (push pair, or feed already fresh this tx)
      }
      // Resolve the same pool the swap will use, then its reference rate feed.
      address pool = poolFor(routes[i].from, routes[i].to, routes[i].factory);
      address rateFeedId = IFPMM(pool).referenceRateFeedID();
      // Empty parameterPayload: no FeeManager on Celo.
      IDataStreamsRelayerFactory(factory).ingest(rateFeedId, signedReportsPerHop[i], "");
    }
  }
}
