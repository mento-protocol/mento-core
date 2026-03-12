// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { TradingLimitsHarness } from "test/utils/harnesses/TradingLimitsHarness.sol";

/**
 * @title TradingLimitsHandler
 * @notice Handler for TradingLimits invariant tests.
 *
 * Models realistic usage: update() is always followed by verify().
 * The state is only committed if BOTH succeed — mirroring how the Broker
 * uses the library in production (update then verify in a single tx).
 *
 * The key invariants we're testing:
 *   - If update+verify succeed, state netflows stay within configured limits
 *   - verify() never silently allows an out-of-bounds state
 */
contract TradingLimitsHandler is CommonBase, StdCheats, StdUtils {
  TradingLimitsHarness public harness;

  ITradingLimits.State internal currentState;
  ITradingLimits.Config internal currentConfig;

  uint8 public constant DECIMALS = 18;

  // Accepted swaps (update+verify both passed)
  uint256 public callCount;
  // Rejected swaps (update passed but verify reverted — expected behaviour)
  uint256 public rejectedCount;

  constructor(TradingLimitsHarness _harness, ITradingLimits.Config memory initConfig) {
    harness = _harness;
    currentConfig = initConfig;
    currentState = ITradingLimits.State({
      lastUpdated0: 0,
      lastUpdated1: 0,
      netflow0: 0,
      netflow1: 0,
      netflowGlobal: 0
    });
  }

  /// @notice Returns a copy of the current trading limits state.
  function getState() external view returns (ITradingLimits.State memory) {
    return currentState;
  }

  /// @notice Returns the current config.
  function getConfig() external view returns (ITradingLimits.Config memory) {
    return currentConfig;
  }

  /**
   * @notice Simulate a swap: call update() then verify().
   * State is committed only if both succeed — matching Broker behaviour.
   */
  function update(int64 rawDelta, uint32 timeWarp) external {
    // Advance time to exercise window resets (bounded to reasonable range)
    timeWarp = uint32(bound(uint256(timeWarp), 0, 7 days));
    vm.warp(block.timestamp + timeWarp);

    // Use a narrower delta range to get a mix of accepted and rejected swaps
    int256 delta = bound(int256(rawDelta), -1e10, 1e10);
    int256 scaledDelta = delta * int256(10 ** uint256(DECIMALS));

    ITradingLimits.State memory nextState;
    bool updateSucceeded;

    try harness.update(currentState, currentConfig, scaledDelta, DECIMALS) returns (
      ITradingLimits.State memory newState
    ) {
      nextState = newState;
      updateSucceeded = true;
    } catch {
      // Arithmetic overflow — skip
      return;
    }

    if (!updateSucceeded) return;

    // Only commit state if verify() also passes
    try harness.verify(nextState, currentConfig) {
      currentState = nextState;
      callCount++;
    } catch {
      // verify() reverted — limit exceeded, this is expected and correct
      rejectedCount++;
    }
  }

  /**
   * @notice Warp past a time window to trigger netflow resets on next update.
   */
  function warpPastWindow(uint8 which) external {
    if (which % 3 == 0 && currentConfig.timestep0 > 0) {
      vm.warp(block.timestamp + uint256(currentConfig.timestep0) + 1);
    } else if (which % 3 == 1 && currentConfig.timestep1 > 0) {
      vm.warp(block.timestamp + uint256(currentConfig.timestep1) + 1);
    }
  }
}
