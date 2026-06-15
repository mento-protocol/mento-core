// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

import { IBreaker } from "../../interfaces/IBreaker.sol";

/**
 * @notice The minimal subset of the SortedOracles interface needed by the breaker.
 * @dev SortedOracles is a Solidity 5.13 contract, thus we can't import the
 *      interface directly, so we use a minimal hand-copied one.
 */
interface ISortedOraclesMin {
  function medianRate(address rateFeedID) external view returns (uint256, uint256);
}

/**
 * @title   Median Delta Breaker V2 (time-normalized slew-rate breaker)
 * @notice  Breaker contract that trips when the on-chain median rate moves faster than a
 *          configured, time-normalized allowance. Unlike the EMA-based MedianDeltaBreaker,
 *          this breaker measures *velocity* (relative move per unit time) rather than absolute
 *          change since the last report, making it correct under the keeperless pull model
 *          where the reporting cadence is irregular.
 *
 *          For each report the allowed relative move is:
 *
 *              allowed = min(maxJump, baseJump + slewPerSecond * Δt)
 *
 *          where Δt is the number of seconds (on `block.timestamp`) since the last report.
 *          The breaker trips when the observed relative move exceeds `allowed`:
 *
 *              relΔ = |current - prev| / prev    (Fixidity 1e24 scale)
 *              trip iff relΔ > allowed
 *
 *          - baseJump:      instantaneous tolerance / Δt=0 floor (jitter, rounding, one tick).
 *          - slewPerSecond: how fast fair value may legitimately move, per second.
 *          - maxJump:       hard ceiling on `allowed`, the genuine-discontinuity circuit.
 *
 * @dev     Implements the IBreaker ABI verbatim so the 0.5.13 BreakerBox consumes it unchanged.
 *          All math is linear fixed-point on the Fixidity 1e24 scale — there is no `exp`, so no
 *          PRBMath dependency. The breaker's Δt uses `block.timestamp` (objective and ungameable),
 *          not the DON `observationsTimestamp` (which the relayer uses for replay/staleness).
 */
contract MedianDeltaBreakerV2 is IBreaker, Ownable {
  /* ==================== Constants ==================== */

  /// @notice Fixidity 1.0 — the scale used by SortedOracles and for all fractions here.
  uint256 public constant FIXED1 = 1e24;

  /* ==================== Events ==================== */

  /// @notice Emitted when the BreakerBox address is updated.
  event BreakerBoxUpdated(address breakerBox);

  /// @notice Emitted when the default cooldown time is updated.
  event DefaultCooldownTimeUpdated(uint256 newCooldownTime);

  /// @notice Emitted when a rate feed's cooldown time is updated.
  event RateFeedCooldownTimeUpdated(address rateFeedID, uint256 newCooldownTime);

  /// @notice Emitted when the default slew parameters are updated.
  event DefaultSlewParametersUpdated(uint256 baseJump, uint256 slewPerSecond, uint256 maxJump);

  /// @notice Emitted when a rate feed's slew parameters are updated.
  event SlewParametersUpdated(address rateFeedID, uint256 baseJump, uint256 slewPerSecond, uint256 maxJump);

  /// @notice Emitted when a rate feed's tracking anchor (lastMedian/lastReportTime) is reset.
  event BreakerStateReset(address rateFeedID);

  /* ==================== Structs ==================== */

  /**
   * @notice Per-feed slew-rate parameters, all Fixidity 1e24 fractions.
   * @custom:member baseJump Instantaneous allowance and Δt=0 floor.
   * @custom:member slewPerSecond Additional allowance accrued per second.
   * @custom:member maxJump Hard ceiling on the total allowance.
   * @custom:member configured Whether this feed has explicit overrides set.
   */
  struct SlewParameters {
    uint256 baseJump;
    uint256 slewPerSecond;
    uint256 maxJump;
    bool configured;
  }

  /* ==================== State Variables ==================== */

  /// @notice Address of the Mento SortedOracles contract.
  ISortedOraclesMin public sortedOracles;

  /// @notice Address of the BreakerBox contract — the only allowed caller of shouldTrigger/shouldReset.
  address public breakerBox;

  /// @notice Default cooldown time. 0 ⇒ manual reset only.
  uint256 public defaultCooldownTime;

  /// @notice Per-feed cooldown override. 0 ⇒ fall back to defaultCooldownTime.
  mapping(address => uint256) public rateFeedCooldownTime;

  /// @notice Default slew parameters, used when a feed has no explicit override.
  SlewParameters public defaultSlewParameters;

  /// @notice Per-feed slew parameter overrides.
  mapping(address => SlewParameters) public slewParameters;

  /// @notice The last accepted median per feed (anchor for the next comparison).
  mapping(address => uint256) public lastMedian;

  /// @notice The `block.timestamp` of the last accepted report per feed.
  mapping(address => uint256) public lastReportTime;

  /* ==================== Errors ==================== */

  error SortedOraclesAddressMustBeSet();
  error BreakerBoxAddressMustBeSet();
  error CallerMustBeBreakerBox();
  error RateFeedAddressMustBeSet();
  error ArrayLengthMismatch();
  error InvalidSlewParameters();

  /* ==================== Constructor ==================== */

  /**
   * @notice Initializes the breaker.
   * @param _defaultCooldownTime Default auto-reset cooldown. Must be > 0 for automatic recovery.
   * @param _sortedOracles The SortedOracles contract to read medians from.
   * @param _breakerBox The BreakerBox contract that drives this breaker.
   * @param _defaultBaseJump Default base jump (Fixidity 1e24 fraction).
   * @param _defaultSlewPerSecond Default slew per second (Fixidity 1e24 fraction).
   * @param _defaultMaxJump Default max jump (Fixidity 1e24 fraction).
   * @param _owner The owner of the breaker.
   */
  constructor(
    uint256 _defaultCooldownTime,
    address _sortedOracles,
    address _breakerBox,
    uint256 _defaultBaseJump,
    uint256 _defaultSlewPerSecond,
    uint256 _defaultMaxJump,
    address _owner
  ) {
    setSortedOracles(_sortedOracles);
    setBreakerBox(_breakerBox);
    _setDefaultCooldownTime(_defaultCooldownTime);
    _setDefaultSlewParameters(_defaultBaseJump, _defaultSlewPerSecond, _defaultMaxJump);
    _transferOwnership(_owner);
  }

  /* ==================== Restricted Functions ==================== */

  /**
   * @notice Sets the address of the SortedOracles contract.
   * @param _sortedOracles The new SortedOracles address.
   */
  function setSortedOracles(address _sortedOracles) public onlyOwner {
    if (_sortedOracles == address(0)) revert SortedOraclesAddressMustBeSet();
    sortedOracles = ISortedOraclesMin(_sortedOracles);
    emit SortedOraclesUpdated(_sortedOracles);
  }

  /**
   * @notice Sets the address of the BreakerBox contract.
   * @param _breakerBox The new BreakerBox address.
   */
  function setBreakerBox(address _breakerBox) public onlyOwner {
    if (_breakerBox == address(0)) revert BreakerBoxAddressMustBeSet();
    breakerBox = _breakerBox;
    emit BreakerBoxUpdated(_breakerBox);
  }

  /**
   * @notice Sets the default cooldown time.
   * @param cooldownTime The new default cooldown. 0 ⇒ manual reset only.
   */
  function setDefaultCooldownTime(uint256 cooldownTime) external onlyOwner {
    _setDefaultCooldownTime(cooldownTime);
  }

  /**
   * @notice Sets the cooldown time for one or more rate feeds.
   * @param rateFeedIDs The targeted rate feeds.
   * @param cooldownTimes The new cooldown times. 0 ⇒ fall back to default.
   */
  function setCooldownTimes(address[] calldata rateFeedIDs, uint256[] calldata cooldownTimes) external onlyOwner {
    if (rateFeedIDs.length != cooldownTimes.length) revert ArrayLengthMismatch();
    for (uint256 i = 0; i < rateFeedIDs.length; i++) {
      if (rateFeedIDs[i] == address(0)) revert RateFeedAddressMustBeSet();
      rateFeedCooldownTime[rateFeedIDs[i]] = cooldownTimes[i];
      emit RateFeedCooldownTimeUpdated(rateFeedIDs[i], cooldownTimes[i]);
    }
  }

  /**
   * @notice Sets the default slew parameters.
   * @param baseJump Default base jump (Fixidity 1e24 fraction).
   * @param slewPerSecond Default slew per second (Fixidity 1e24 fraction).
   * @param maxJump Default max jump (Fixidity 1e24 fraction).
   */
  function setDefaultSlewParameters(uint256 baseJump, uint256 slewPerSecond, uint256 maxJump) external onlyOwner {
    _setDefaultSlewParameters(baseJump, slewPerSecond, maxJump);
  }

  /**
   * @notice Sets the slew parameters for a rate feed.
   * @param rateFeedID The targeted rate feed.
   * @param baseJump Base jump (Fixidity 1e24 fraction).
   * @param slewPerSecond Slew per second (Fixidity 1e24 fraction).
   * @param maxJump Max jump (Fixidity 1e24 fraction).
   */
  function setSlewParameters(
    address rateFeedID,
    uint256 baseJump,
    uint256 slewPerSecond,
    uint256 maxJump
  ) external onlyOwner {
    if (rateFeedID == address(0)) revert RateFeedAddressMustBeSet();
    if (baseJump > maxJump || maxJump == 0) revert InvalidSlewParameters();
    slewParameters[rateFeedID] = SlewParameters(baseJump, slewPerSecond, maxJump, true);
    emit SlewParametersUpdated(rateFeedID, baseJump, slewPerSecond, maxJump);
  }

  /**
   * @notice Resets a rate feed's tracking anchor so the next report re-seeds.
   * @param rateFeedID The targeted rate feed.
   * @dev Should be called when the breaker is disabled / re-enabled for a feed so it does
   *      not compare a fresh report against a stale anchor (see plan §2.3 assumption b).
   */
  function resetBreakerState(address rateFeedID) external onlyOwner {
    if (rateFeedID == address(0)) revert RateFeedAddressMustBeSet();
    lastMedian[rateFeedID] = 0;
    lastReportTime[rateFeedID] = 0;
    emit BreakerStateReset(rateFeedID);
  }

  /* ==================== View Functions ==================== */

  /**
   * @notice Returns the cooldown time for a rate feed.
   * @param rateFeedID The targeted rate feed.
   * @return The feed-specific cooldown, or the default if none is set.
   */
  function getCooldown(address rateFeedID) external view returns (uint256) {
    uint256 _rateFeedCooldownTime = rateFeedCooldownTime[rateFeedID];
    if (_rateFeedCooldownTime == 0) {
      return defaultCooldownTime;
    }
    return _rateFeedCooldownTime;
  }

  /**
   * @notice Returns the effective slew parameters for a rate feed (override or default).
   * @param rateFeedID The targeted rate feed.
   * @return baseJump The effective base jump.
   * @return slewPerSecond The effective slew per second.
   * @return maxJump The effective max jump.
   */
  function getSlewParameters(
    address rateFeedID
  ) public view returns (uint256 baseJump, uint256 slewPerSecond, uint256 maxJump) {
    SlewParameters memory p = slewParameters[rateFeedID];
    if (!p.configured) {
      p = defaultSlewParameters;
    }
    return (p.baseJump, p.slewPerSecond, p.maxJump);
  }

  /**
   * @notice Computes the time-normalized allowed relative move.
   * @dev Pure helper exposed for off-chain validation against the reference model.
   * @param baseJump Base jump (Fixidity 1e24 fraction).
   * @param slewPerSecond Slew per second (Fixidity 1e24 fraction).
   * @param maxJump Max jump (Fixidity 1e24 fraction).
   * @param deltaT Seconds since the last report.
   * @return allowed The allowed relative move, min(maxJump, baseJump + slewPerSecond * Δt).
   */
  function calculateAllowed(
    uint256 baseJump,
    uint256 slewPerSecond,
    uint256 maxJump,
    uint256 deltaT
  ) public pure returns (uint256 allowed) {
    allowed = baseJump + slewPerSecond * deltaT;
    if (allowed > maxJump) {
      allowed = maxJump;
    }
  }

  /**
   * @notice Computes the relative move between two medians on the Fixidity 1e24 scale.
   * @param prev The previous (anchor) median, must be > 0.
   * @param current The current median.
   * @return The relative move |current - prev| / prev as a Fixidity 1e24 fraction.
   */
  function calculateRelativeDelta(uint256 prev, uint256 current) public pure returns (uint256) {
    uint256 absDelta = current > prev ? current - prev : prev - current;
    return (absDelta * FIXED1) / prev;
  }

  /* ==================== Breaker Logic ==================== */

  /**
   * @notice Checks whether the latest median moved faster than the time-normalized allowance.
   * @dev Mutates the per-feed anchor (lastMedian/lastReportTime) on every call, exactly once
   *      per report (BreakerBox calls either shouldTrigger or shouldReset, never both).
   * @param rateFeedID The rate feed to check.
   * @return triggerBreaker True if the breaker should trip.
   */
  function shouldTrigger(address rateFeedID) public returns (bool triggerBreaker) {
    if (msg.sender != breakerBox) revert CallerMustBeBreakerBox();

    // slither-disable-next-line unused-return
    (uint256 currentMedian, ) = sortedOracles.medianRate(rateFeedID);

    uint256 prev = lastMedian[rateFeedID];
    if (prev == 0) {
      // First observation for this feed: seed the anchor, do not trip.
      lastMedian[rateFeedID] = currentMedian;
      // solhint-disable-next-line not-rely-on-time
      lastReportTime[rateFeedID] = block.timestamp;
      return false;
    }

    // solhint-disable-next-line not-rely-on-time
    uint256 deltaT = block.timestamp - lastReportTime[rateFeedID];
    uint256 relDelta = calculateRelativeDelta(prev, currentMedian);

    (uint256 baseJump, uint256 slewPerSecond, uint256 maxJump) = getSlewParameters(rateFeedID);
    uint256 allowed = calculateAllowed(baseJump, slewPerSecond, maxJump, deltaT);

    lastMedian[rateFeedID] = currentMedian;
    // solhint-disable-next-line not-rely-on-time
    lastReportTime[rateFeedID] = block.timestamp;

    return relDelta > allowed;
  }

  /**
   * @notice Checks whether the breaker may reset for a rate feed.
   * @param rateFeedID The rate feed to check.
   * @return resetBreaker True if the latest move is back within the (time-scaled) allowance.
   */
  function shouldReset(address rateFeedID) external returns (bool resetBreaker) {
    return !shouldTrigger(rateFeedID);
  }

  /* ==================== Internal Functions ==================== */

  function _setDefaultCooldownTime(uint256 cooldownTime) internal {
    defaultCooldownTime = cooldownTime;
    emit DefaultCooldownTimeUpdated(cooldownTime);
  }

  function _setDefaultSlewParameters(uint256 baseJump, uint256 slewPerSecond, uint256 maxJump) internal {
    if (baseJump > maxJump || maxJump == 0) revert InvalidSlewParameters();
    defaultSlewParameters = SlewParameters(baseJump, slewPerSecond, maxJump, true);
    emit DefaultSlewParametersUpdated(baseJump, slewPerSecond, maxJump);
  }
}
