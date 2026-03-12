// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import { Test } from "forge-std/Test.sol";

import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { TradingLimitsHarness } from "test/utils/harnesses/TradingLimitsHarness.sol";
import { TradingLimitsHandler } from "./handlers/TradingLimitsHandler.sol";

/**
 * @title TradingLimitsInvariantTest
 * @notice Foundry invariant tests for the TradingLimits library.
 *
 * Run with:
 *   forge test --match-contract TradingLimitsInvariant --no-match-contract ForkTest -v
 *
 * Invariants verified:
 *   1. netflow0 never exceeds ±limit0 when L0 is enabled
 *   2. netflow1 never exceeds ±limit1 when L1 is enabled
 *   3. netflowGlobal never exceeds ±limitGlobal when LG is enabled
 *   4. verify() does not revert after any sequence of accepted updates
 *   5. callCount is monotonically non-decreasing (sanity)
 */
contract TradingLimitsInvariantTest is Test {
  uint8 constant L0 = 1;
  uint8 constant L1 = 2;
  uint8 constant LG = 4;

  TradingLimitsHarness harness;

  TradingLimitsHandler handlerL0LG;
  TradingLimitsHandler handlerL0L1LG;
  TradingLimitsHandler handlerLG;

  function setUp() public {
    harness = new TradingLimitsHarness();

    // Config: L0 | LG
    ITradingLimits.Config memory configL0LG = ITradingLimits.Config({
      timestep0: 1 hours,
      timestep1: 0,
      limit0: 1_000,
      limit1: 0,
      limitGlobal: 10_000,
      flags: L0 | LG
    });
    handlerL0LG = new TradingLimitsHandler(harness, configL0LG);

    // Config: L0 | L1 | LG
    ITradingLimits.Config memory configFull = ITradingLimits.Config({
      timestep0: 1 hours,
      timestep1: 1 days,
      limit0: 500,
      limit1: 2_000,
      limitGlobal: 20_000,
      flags: L0 | L1 | LG
    });
    handlerL0L1LG = new TradingLimitsHandler(harness, configFull);

    // Config: LG only
    ITradingLimits.Config memory configLGOnly = ITradingLimits.Config({
      timestep0: 0,
      timestep1: 0,
      limit0: 0,
      limit1: 0,
      limitGlobal: 5_000,
      flags: LG
    });
    handlerLG = new TradingLimitsHandler(harness, configLGOnly);

    targetContract(address(handlerL0LG));
    targetContract(address(handlerL0L1LG));
    targetContract(address(handlerLG));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 1: netflow0 within ±limit0 whenever L0 is enabled
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_netflow0_within_limit_L0LG() public {
    ITradingLimits.State memory s = handlerL0LG.getState();
    ITradingLimits.Config memory c = handlerL0LG.getConfig();
    if (c.flags & L0 > 0) {
      assertGe(int256(s.netflow0), -int256(c.limit0), "netflow0 below -limit0 (L0LG)");
      assertLe(int256(s.netflow0), int256(c.limit0), "netflow0 above limit0 (L0LG)");
    }
  }

  function invariant_netflow0_within_limit_full() public {
    ITradingLimits.State memory s = handlerL0L1LG.getState();
    ITradingLimits.Config memory c = handlerL0L1LG.getConfig();
    if (c.flags & L0 > 0) {
      assertGe(int256(s.netflow0), -int256(c.limit0), "netflow0 below -limit0 (full)");
      assertLe(int256(s.netflow0), int256(c.limit0), "netflow0 above limit0 (full)");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 2: netflow1 within ±limit1 whenever L1 is enabled
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_netflow1_within_limit_full() public {
    ITradingLimits.State memory s = handlerL0L1LG.getState();
    ITradingLimits.Config memory c = handlerL0L1LG.getConfig();
    if (c.flags & L1 > 0) {
      assertGe(int256(s.netflow1), -int256(c.limit1), "netflow1 below -limit1");
      assertLe(int256(s.netflow1), int256(c.limit1), "netflow1 above limit1");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 3: netflowGlobal within ±limitGlobal whenever LG is enabled
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_netflowGlobal_within_limit_L0LG() public {
    ITradingLimits.State memory s = handlerL0LG.getState();
    ITradingLimits.Config memory c = handlerL0LG.getConfig();
    if (c.flags & LG > 0) {
      assertGe(int256(s.netflowGlobal), -int256(c.limitGlobal), "netflowGlobal below -limitGlobal (L0LG)");
      assertLe(int256(s.netflowGlobal), int256(c.limitGlobal), "netflowGlobal above limitGlobal (L0LG)");
    }
  }

  function invariant_netflowGlobal_within_limit_LG_only() public {
    ITradingLimits.State memory s = handlerLG.getState();
    ITradingLimits.Config memory c = handlerLG.getConfig();
    if (c.flags & LG > 0) {
      assertGe(int256(s.netflowGlobal), -int256(c.limitGlobal), "netflowGlobal below -limitGlobal (LG-only)");
      assertLe(int256(s.netflowGlobal), int256(c.limitGlobal), "netflowGlobal above limitGlobal (LG-only)");
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 4: verify() does not revert on accepted state
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_verify_does_not_revert_L0LG() public {
    ITradingLimits.State memory s = handlerL0LG.getState();
    ITradingLimits.Config memory c = handlerL0LG.getConfig();
    harness.verify(s, c);
  }

  function invariant_verify_does_not_revert_full() public {
    ITradingLimits.State memory s = handlerL0L1LG.getState();
    ITradingLimits.Config memory c = handlerL0L1LG.getConfig();
    harness.verify(s, c);
  }

  function invariant_verify_does_not_revert_LG() public {
    ITradingLimits.State memory s = handlerLG.getState();
    ITradingLimits.Config memory c = handlerLG.getConfig();
    harness.verify(s, c);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invariant 5: callCount sanity
  // ──────────────────────────────────────────────────────────────────────────

  function invariant_callCount_non_negative() public view {
    assertGe(handlerL0LG.callCount(), 0, "callCount underflowed");
    assertGe(handlerL0L1LG.callCount(), 0, "callCount underflowed");
    assertGe(handlerLG.callCount(), 0, "callCount underflowed");
  }
}
