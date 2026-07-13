// SPDX-License-Identifier: BUSL-1.1
// solhint-disable immutable-vars-naming
pragma solidity 0.8.19;

import { IPullOracleRelayer } from "../interfaces/IPullOracleRelayer.sol";
import { IPullOracleAdapter } from "../interfaces/IPullOracleAdapter.sol";
import { UD60x18, ud, intoUint256 } from "prb/math/UD60x18.sol";

/**
 * @notice The minimal subset of the SortedOracles interface needed by the
 * relayer.
 * @dev SortedOracles is a Solidity 5.13 contract, thus we can't import the
 * interface directly, so we use a minimal hand-copied one.
 * See https://github.com/mento-protocol/mento-core/blob/develop/contracts/common/SortedOracles.sol
 */
interface ISortedOraclesMin {
  function report(address rateFeedId, uint256 value, address lesserKey, address greaterKey) external;

  function getRates(address rateFeedId) external returns (address[] memory, uint256[] memory, uint256[] memory);

  function medianTimestamp(address rateFeedId) external view returns (uint256);

  function getTokenReportExpirySeconds(address rateFeedId) external view returns (uint256);

  function removeExpiredReports(address rateFeedId, uint256 n) external;
}

/**
 * @title PullOracleRelayerV1
 * @notice The PullOracleRelayerV1 relays rate feed data from one or more pull-oracle price updates
 * to the SortedOracles contract. A separate instance should be deployed for each rate feed.
 * @dev Mirrors ChainlinkRelayerV1 in structure: same CREATE2 deployment via factory, same immutable
 * leg storage pattern (up to 4), same reportRate() logic for writing to SortedOracles. The source
 * differs — instead of reading latestRoundData() from Chainlink push aggregators, this contract
 * accepts a caller-supplied provider update blob, verifies it via the configured IPullOracleAdapter
 * (Chainlink Data Streams, Pyth, RedStone, ...), and writes the composed rate. All provider
 * specifics live in the adapter; this contract only sees normalized (price, obsTs, expiry) tuples.
 *
 * relay() is permissionless: it is called by the swap transaction itself (as a
 * state-changing pre-step before the view oracle read), by arbitrageurs, or by the
 * dapp before showing a quote. There is no Mento-operated keeper.
 *
 * Replay semantics on compositeObs (= min leg observationsTimestamp):
 *   > lastObservationsTimestamp → accepted, rate written.
 *   == lastObservationsTimestamp → idempotent no-op, emits ReportSkippedIdempotent.
 *   < lastObservationsTimestamp → reverts StaleReport.
 */
contract PullOracleRelayerV1 is IPullOracleRelayer {
  /**
   * @notice The number of digits after the decimal point in FixidityLib values,
   * as used by SortedOracles.
   * @dev See contracts/common/FixidityLib.sol
   */
  uint256 private constant UD60X18_TO_FIXIDITY_SCALE = 1e6; // 10 ** (24 - 18)

  /// @notice The rateFeedId this relayer relays for.
  address public immutable rateFeedId;

  /// @notice The address of the SortedOracles contract to report to.
  address public immutable sortedOracles;

  /// @notice The IPullOracleAdapter that verifies provider update blobs for this relayer.
  address public immutable adapter;

  /**
   * @notice Maximum spread allowed between the oldest and newest leg
   * observationsTimestamp, in seconds.
   * @dev Only relevant when legCount > 1.
   */
  uint256 public immutable maxTimestampSpread;

  /**
   * @notice Maximum age of a report's observationsTimestamp relative to
   * block.timestamp, in seconds.
   */
  uint256 public immutable maxStaleness;

  /**
   * @dev We store an array of up to four OracleLeg structs in the following
   * immutable variables. feedId<i> stores the i-th OracleLeg.feedId member.
   * invert<i> stores the i-th OracleLeg.invert member. legCount stores the
   * length of the array. These are built back up into an in-memory array in
   * the buildLegArray function.
   */

  /// @notice The provider feedIds this contract relays data for.
  bytes32 private immutable feedId0;
  bytes32 private immutable feedId1;
  bytes32 private immutable feedId2;
  bytes32 private immutable feedId3;

  /// @notice The invert setting for each leg, if true it flips the rate, i.e. USD/JPY -> JPY/USD.
  bool private immutable invert0;
  bool private immutable invert1;
  bool private immutable invert2;
  bool private immutable invert3;

  /// @notice The number of legs provided during construction: 1 <= legCount <= 4.
  uint256 private immutable legCount;

  /**
   * @notice Human-readable description of the rate feed.
   * @dev Should only be used off-chain for easier debugging / UI generation,
   * thus the only storage related gas spend occurs in the constructor.
   */
  string public rateFeedDescription;

  /// @notice The composite observationsTimestamp of the last accepted relay call.
  uint256 public lastObservationsTimestamp;

  /// @notice Used when an empty array of legs is passed into the constructor.
  error NoLegs();

  /// @notice Used when more than four legs are passed into the constructor.
  error TooManyLegs();

  /// @notice Used when a) there is more than 1 leg and the maxTimestampSpread is 0,
  /// OR b) when there is only 1 leg and the maxTimestampSpread is not 0.
  error InvalidMaxTimestampSpread();

  /// @notice Used when a leg's feedId is bytes32(0).
  error InvalidFeedId();

  /// @notice Used when the adapter's response arrays are not aligned to the leg count.
  error AdapterResponseMismatch();

  /// @notice Used when the adapter returns a zero price (defense in depth; adapters must revert
  /// on non-positive prices themselves).
  error InvalidPrice();

  /// @notice Used when block.timestamp exceeds a report's expiry.
  error ExpiredSignature();

  /**
   * @notice Used when a report's observationsTimestamp is older than maxStaleness
   * relative to block.timestamp.
   */
  error ReportTooStale();

  /// @notice Used when a report's observationsTimestamp is in the future relative to block.timestamp.
  error FutureReport();

  /**
   * @notice Used when the spread between the earliest and latest observationsTimestamp
   * across all legs is above the maximum allowed.
   */
  error TimestampSpreadTooHigh();

  /**
   * @notice Used when the composite observationsTimestamp is strictly less than
   * lastObservationsTimestamp (replay of an older report set).
   */
  error StaleReport();

  /**
   * @notice Used when trying to recover from a lesser/greater revert and there are
   * too many existing reports in SortedOracles.
   */
  error TooManyExistingReports();

  /**
   * @notice Initializes the contract and sets immutable parameters.
   * @param _rateFeedId ID of the rate feed this relayer instance relays for.
   * @param _rateFeedDescription The human-readable description of the reported rate feed.
   * @param _sortedOracles Address of the SortedOracles contract to relay to.
   * @param _adapter Address of the IPullOracleAdapter that verifies update blobs.
   * @param _maxTimestampSpread Max difference in seconds between the earliest and
   *        latest observationsTimestamp across all legs. Must be 0 for single-leg relayers.
   * @param _maxStaleness Max age in seconds of a report's observationsTimestamp
   *        relative to block.timestamp.
   * @param _legs Array of OracleLeg structs defining the price composition path.
   */
  constructor(
    address _rateFeedId,
    string memory _rateFeedDescription,
    address _sortedOracles,
    address _adapter,
    uint256 _maxTimestampSpread,
    uint256 _maxStaleness,
    OracleLeg[] memory _legs
  ) {
    rateFeedId = _rateFeedId;
    rateFeedDescription = _rateFeedDescription;
    sortedOracles = _sortedOracles;
    adapter = _adapter;
    maxTimestampSpread = _maxTimestampSpread;
    maxStaleness = _maxStaleness;

    legCount = _legs.length;
    if (legCount == 0) revert NoLegs();
    if (legCount > 4) revert TooManyLegs();
    if ((legCount > 1 && _maxTimestampSpread == 0) || (legCount == 1 && _maxTimestampSpread != 0)) {
      revert InvalidMaxTimestampSpread();
    }

    OracleLeg[] memory legs = new OracleLeg[](4);
    for (uint256 i = 0; i < _legs.length; i++) {
      if (_legs[i].feedId == bytes32(0)) revert InvalidFeedId();
      legs[i] = _legs[i];
    }

    feedId0 = legs[0].feedId;
    feedId1 = legs[1].feedId;
    feedId2 = legs[2].feedId;
    feedId3 = legs[3].feedId;
    invert0 = legs[0].invert;
    invert1 = legs[1].invert;
    invert2 = legs[2].invert;
    invert3 = legs[3].invert;
  }

  /**
   * @notice Get the oracle legs and their invert settings.
   * @return An array of OracleLeg segments that compose the price path.
   */
  function getLegs() external view returns (OracleLeg[] memory) {
    return buildLegArray();
  }

  /**
   * @notice Verifies a provider update blob and writes the composed rate to SortedOracles.
   * @dev Delegates verification + decoding to the configured IPullOracleAdapter, then validates
   * freshness per leg (expiry, staleness, future-timestamp) and the cross-leg spread. Legs are
   * multiplied together with optional inversion to produce a composed rate. On completion,
   * SortedOracles.report() triggers BreakerBox.checkAndSetBreakers() as a side effect.
   * msg.value is forwarded to the adapter to cover provider verification fees (0 for fee-less
   * providers, which reject a non-zero value).
   * @param updateData Provider-specific update blob covering all legs, in leg order.
   */
  function relay(bytes calldata updateData) external payable {
    (UD60x18 composedRate, uint256 compositeObs) = composeRate(updateData);

    if (compositeObs < lastObservationsTimestamp) revert StaleReport();
    if (compositeObs == lastObservationsTimestamp) {
      emit ReportSkippedIdempotent(compositeObs);
      return;
    }

    lastObservationsTimestamp = compositeObs;
    uint256 rate = intoUint256(composedRate) * UD60X18_TO_FIXIDITY_SCALE;
    reportRate(rate);
    emit Relayed(rateFeedId, rate, compositeObs, msg.sender);
  }

  /**
   * @notice Verifies the update blob via the adapter and composes the legs into a single rate.
   * @dev Enforces the per-leg invariants (positive price, expiry, staleness, future-timestamp)
   * and the cross-leg maxTimestampSpread. The composite observationsTimestamp is the oldest leg's,
   * so the weakest (least fresh) leg defines the freshness of the whole composite.
   * @param updateData Provider-specific update blob covering all legs.
   * @return composedRate The product of all legs (each optionally inverted), as a UD60x18 value.
   * @return compositeObs The oldest leg observationsTimestamp across all legs.
   */
  function composeRate(bytes calldata updateData) internal returns (UD60x18 composedRate, uint256 compositeObs) {
    OracleLeg[] memory legs = buildLegArray();
    bytes32[] memory feedIds = new bytes32[](legCount);
    for (uint256 i = 0; i < legCount; i++) {
      feedIds[i] = legs[i].feedId;
    }

    (uint256[] memory prices, uint256[] memory observationsTimestamps, uint256[] memory expiries) = IPullOracleAdapter(
      adapter
    ).verify{ value: msg.value }(feedIds, updateData);
    if (prices.length != legCount || observationsTimestamps.length != legCount || expiries.length != legCount)
      revert AdapterResponseMismatch();

    composedRate = ud(1e18);
    uint256 oldestObs = type(uint256).max;
    uint256 newestObs = 0;

    for (uint256 i = 0; i < legCount; i++) {
      UD60x18 legPrice = validateLeg(legs[i], prices[i], observationsTimestamps[i], expiries[i]);
      composedRate = composedRate.mul(legPrice);
      if (observationsTimestamps[i] < oldestObs) oldestObs = observationsTimestamps[i];
      if (observationsTimestamps[i] > newestObs) newestObs = observationsTimestamps[i];
    }

    if (newestObs - oldestObs > maxTimestampSpread) revert TimestampSpreadTooHigh();
    compositeObs = oldestObs;
  }

  /**
   * @notice Validates a single leg's normalized observation and returns the (optionally inverted)
   * leg price.
   * @dev The adapter guarantees feedId binding and price positivity; this enforces the relayer's
   * uniform freshness policy on top (the single place staleness rules live, across providers).
   * @param leg The OracleLeg (invert flag) for this position.
   * @param price The adapter-normalized price (1e18 fixed-point).
   * @param observationsTimestamp When the provider observed this leg's price (unix seconds).
   * @param expiresAt Hard report expiry (unix seconds; type(uint32).max when the provider has none).
   * @return legPrice The (optionally inverted) price as a UD60x18 value.
   */
  function validateLeg(
    OracleLeg memory leg,
    uint256 price,
    uint256 observationsTimestamp,
    uint256 expiresAt
  ) internal view returns (UD60x18 legPrice) {
    if (price == 0) revert InvalidPrice();
    // A future-dated observation would underflow the staleness subtraction below (0.8.x checked
    // math) and revert opaquely; reject it explicitly with a clear error instead.
    // solhint-disable-next-line not-rely-on-time
    if (observationsTimestamp > block.timestamp) revert FutureReport();
    // solhint-disable-next-line not-rely-on-time
    if (block.timestamp > expiresAt) revert ExpiredSignature();
    // solhint-disable-next-line not-rely-on-time
    if (block.timestamp - observationsTimestamp > maxStaleness) revert ReportTooStale();

    legPrice = ud(price);
    if (leg.invert) legPrice = legPrice.inv();
  }

  /**
   * @notice Compose immutable variables into an in-memory array for better handling.
   * @return legs An array of OracleLeg structs.
   */
  function buildLegArray() internal view returns (OracleLeg[] memory legs) {
    legs = new OracleLeg[](legCount);
    unchecked {
      legs[0] = OracleLeg(feedId0, invert0);
      if (legCount > 1) {
        legs[1] = OracleLeg(feedId1, invert1);
        if (legCount > 2) {
          legs[2] = OracleLeg(feedId2, invert2);
          if (legCount > 3) {
            legs[3] = OracleLeg(feedId3, invert3);
          }
        }
      }
    }
  }

  /**
   * @notice Report by looking up existing reports and building the lesser and greater keys.
   * @dev Depending on the state in SortedOracles we can be in the:
   *   - Happy path: No reports, or a single report from this relayer.
   *     We can report with lesser and greater keys as address(0)
   *   - Unhappy path: There are reports from other oracles.
   *     We restrain this path by only computing lesser and greater keys when there is
   *     at most one report from a different oracle.
   *     We also attempt to expire reports in order to get back to the happy path.
   *
   *   DUAL-RUN OPERATIONAL CONSTRAINT: this only tolerates a feed with at most two reporters
   *   total, at most one of which is foreign to this relayer. During the push->pull migration a
   *   feed may briefly carry both the legacy push ChainlinkRelayer and this pull relayer; that is
   *   fine (numRates == 2, one is self). But if a migrating feed still has any *third* legacy
   *   oracle, numRates > 2 reverts TooManyExistingReports() and the write path is dead. Before
   *   enabling the pull relayer on a feed, confirm it has no leftover third oracle.
   * @param rate The rate to report.
   */
  function reportRate(uint256 rate) internal {
    // slither-disable-next-line unused-return
    (address[] memory oracles, uint256[] memory rates, ) = ISortedOraclesMin(sortedOracles).getRates(rateFeedId);
    uint256 numRates = oracles.length;

    if (numRates == 0 || (numRates == 1 && oracles[0] == address(this))) {
      // Happy path: SortedOracles is empty, or there is a single report from this relayer.
      ISortedOraclesMin(sortedOracles).report(rateFeedId, rate, address(0), address(0));
      return;
    }

    if (numRates > 2 || (numRates == 2 && oracles[0] != address(this) && oracles[1] != address(this))) {
      revert TooManyExistingReports();
    }

    // At this point we have ensured that either:
    // - There is a single report from another oracle.
    // - There are two reports and one is from this relayer.

    address otherOracle;
    uint256 otherRate;

    if (numRates == 1 || oracles[0] != address(this)) {
      otherOracle = oracles[0];
      otherRate = rates[0];
    } else {
      otherOracle = oracles[1];
      otherRate = rates[1];
    }

    // slither-disable-start uninitialized-local
    address lesserKey;
    address greaterKey;
    // slither-disable-end uninitialized-local

    if (otherRate < rate) {
      lesserKey = otherOracle;
    } else {
      greaterKey = otherOracle;
    }

    ISortedOraclesMin(sortedOracles).report(rateFeedId, rate, lesserKey, greaterKey);
    ISortedOraclesMin(sortedOracles).removeExpiredReports(rateFeedId, 1);
  }
}
