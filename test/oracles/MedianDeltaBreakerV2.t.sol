// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8.19;

import { Test } from "mento-std/Test.sol";

import { MedianDeltaBreakerV2 } from "contracts/oracles/breakers/MedianDeltaBreakerV2.sol";
import { MockSortedOracles } from "test/utils/mocks/MockSortedOracles.sol";

contract MedianDeltaBreakerV2Test is Test {
  // FX-ish preset (Fixidity 1e24). Identical to test/references/median_delta_breaker_v2_reference.py
  uint256 constant FX_BASE = 5e21; // 0.5%
  uint256 constant FX_SLEW = 5555555555555555555; // (2e22)/3600, 2%/hour per-second
  uint256 constant FX_MAX = 5e22; // 5%

  // Crypto-ish preset.
  uint256 constant CR_BASE = 1e22; // 1%
  uint256 constant CR_SLEW = 27777777777777777777; // (1e23)/3600, 10%/hour per-second
  uint256 constant CR_MAX = 2e23; // 20%

  // 1e-9 relative tolerance, expressed in forge-std's 1e18 = 100% scale.
  uint256 constant REL_TOL = 1e9;

  uint256 constant FIX1 = 1e24;

  MockSortedOracles sortedOracles;
  MedianDeltaBreakerV2 breaker;

  address rateFeedId = makeAddr("rateFeed");
  address otherFeed = makeAddr("otherFeed");
  uint256 defaultCooldown = 300;

  function setUp() public {
    vm.warp(1_000_000);
    sortedOracles = new MockSortedOracles();
    // breakerBox = address(this) so this test can call shouldTrigger/shouldReset directly.
    breaker = new MedianDeltaBreakerV2(
      defaultCooldown,
      address(sortedOracles),
      address(this),
      FX_BASE,
      FX_SLEW,
      FX_MAX,
      address(this)
    );
  }

  // ---- helpers ----

  function setMedian(uint256 m) internal {
    sortedOracles.setMedianRate(rateFeedId, m);
  }

  function trigger() internal returns (bool) {
    return breaker.shouldTrigger(rateFeedId);
  }

  /// @notice Seed the anchor at `m` and the current block time.
  function seed(uint256 m) internal {
    setMedian(m);
    bool tripped = trigger();
    assertFalse(tripped, "seeding must not trip");
  }

  /// @notice Advance `dt` seconds, set the new median, and evaluate the breaker.
  function moveAfter(uint256 dt, uint256 newMedian) internal returns (bool) {
    vm.warp(block.timestamp + dt);
    setMedian(newMedian);
    return trigger();
  }
}

contract MedianDeltaBreakerV2Test_pureMath is MedianDeltaBreakerV2Test {
  struct AllowedRow {
    uint256 baseJump;
    uint256 slew;
    uint256 maxJump;
    uint256 dt;
    uint256 refAllowed;
  }

  // Reference values produced by test/references/median_delta_breaker_v2_reference.py (numpy float model).
  function test_calculateAllowed_matchesNumpyReference() public view {
    AllowedRow[11] memory rows = [
      AllowedRow(FX_BASE, FX_SLEW, FX_MAX, 0, 5000000000000000000000),
      AllowedRow(FX_BASE, FX_SLEW, FX_MAX, 30, 5166666666666667016192),
      AllowedRow(FX_BASE, FX_SLEW, FX_MAX, 300, 6666666666666667016192),
      AllowedRow(FX_BASE, FX_SLEW, FX_MAX, 3600, 25000000000000002097152),
      AllowedRow(FX_BASE, FX_SLEW, FX_MAX, 10800, 50000000000000004194304),
      AllowedRow(FX_BASE, FX_SLEW, FX_MAX, 100000, 50000000000000004194304),
      AllowedRow(CR_BASE, CR_SLEW, CR_MAX, 0, 10000000000000000000000),
      AllowedRow(CR_BASE, CR_SLEW, CR_MAX, 60, 11666666666666665967616),
      AllowedRow(CR_BASE, CR_SLEW, CR_MAX, 600, 26666666666666663870464),
      AllowedRow(CR_BASE, CR_SLEW, CR_MAX, 3600, 110000000000000004194304),
      AllowedRow(CR_BASE, CR_SLEW, CR_MAX, 7200, 200000000000000016777216)
    ];
    for (uint256 i = 0; i < rows.length; i++) {
      uint256 got = breaker.calculateAllowed(rows[i].baseJump, rows[i].slew, rows[i].maxJump, rows[i].dt);
      assertApproxEqRel(got, rows[i].refAllowed, REL_TOL, "allowed mismatch vs numpy");
    }
  }

  struct RelRow {
    uint256 prev;
    uint256 current;
    uint256 refRel;
  }

  function test_calculateRelativeDelta_matchesNumpyReference() public view {
    // +3%, -3%, +0.5%, +20% (flat=0 checked separately with exact equality).
    RelRow[4] memory rows = [
      RelRow(1000000000000000000000000, 1030000000000000000000000, 30000000000000020971520),
      RelRow(1000000000000000000000000, 970000000000000000000000, 30000000000000020971520),
      RelRow(2000000000000000000000000, 2010000000000000000000000, 4999999999999981125632),
      RelRow(800000000000000000000000, 960000000000000000000000, 200000000000000083886080)
    ];
    for (uint256 i = 0; i < rows.length; i++) {
      uint256 got = breaker.calculateRelativeDelta(rows[i].prev, rows[i].current);
      assertApproxEqRel(got, rows[i].refRel, REL_TOL, "relDelta mismatch vs numpy");
    }
    // flat move is exactly zero.
    assertEq(breaker.calculateRelativeDelta(15e23, 15e23), 0);
  }
}

contract MedianDeltaBreakerV2Test_slew is MedianDeltaBreakerV2Test {
  // Scenario 1: seeding — first observation never trips and sets the anchor.
  function test_seeding_setsAnchorAndDoesNotTrip() public {
    setMedian(FIX1);
    bool tripped = trigger();
    assertFalse(tripped);
    assertEq(breaker.lastMedian(rateFeedId), FIX1);
    assertEq(breaker.lastReportTime(rateFeedId), block.timestamp);
  }

  // Scenario 2: short-Δt flash move trips.
  function test_shortDeltaFlash_trips() public {
    seed(FIX1);
    // +3% over 30s; allowed ≈ 0.5% + 30*slew ≈ 0.5166% << 3% → trip.
    bool tripped = moveAfter(30, 103e22);
    assertTrue(tripped);
  }

  // Scenario 3: long quiet gap with a legitimate slow move is allowed.
  function test_longGapDriftWithinSlew_allowed() public {
    seed(FIX1);
    // +3% over 3h (10800s); allowed = min(5%, 0.5% + 10800*slew) = 5% > 3% → allow.
    bool tripped = moveAfter(10800, 103e22);
    assertFalse(tripped);
  }

  // Scenario 4a: Δt=0 baseJump floor — a move above baseJump in the same block trips.
  function test_zeroDelta_aboveBaseJump_trips() public {
    seed(FIX1);
    // same block, +0.6% > baseJump(0.5%) → trip.
    bool tripped = moveAfter(0, 1006e21);
    assertTrue(tripped);
  }

  // Scenario 4b: Δt=0 baseJump floor — a move below baseJump in the same block is allowed.
  function test_zeroDelta_belowBaseJump_allowed() public {
    seed(FIX1);
    // same block, +0.4% < baseJump(0.5%) → allow.
    bool tripped = moveAfter(0, 1004e21);
    assertFalse(tripped);
  }

  // Scenario 5: maxJump ceiling — an enormous gap cannot license a move beyond maxJump.
  function test_maxJumpCeiling_trips() public {
    seed(FIX1);
    // +6% > maxJump(5%) even after a huge gap → trip.
    bool tripped = moveAfter(1_000_000, 106e22);
    assertTrue(tripped);
  }

  // Scenario 6: relΔ == allowed boundary is allowed (strict >).
  function test_relDeltaEqualsAllowed_boundary_allowed() public {
    seed(FIX1);
    // dt=0 → allowed = baseJump = 0.5%. Move of exactly +0.5% → relΔ == allowed → allow.
    uint256 exact = FIX1 + FX_BASE; // prev=1e24 ⇒ relΔ(fixidity) == |cur-prev|
    bool tripped = moveAfter(0, exact);
    assertFalse(tripped, "relDelta == allowed must not trip");
  }

  function test_relDeltaJustAboveAllowed_boundary_trips() public {
    seed(FIX1);
    uint256 justOver = FIX1 + FX_BASE + 1;
    bool tripped = moveAfter(0, justOver);
    assertTrue(tripped, "relDelta == allowed + 1 must trip");
  }

  // Scenario 7: reset path — after a trip, a back-in-band move resets (shouldReset == true).
  function test_resetPath_backInBand_resets() public {
    seed(FIX1);
    bool tripped = moveAfter(30, 103e22); // flash trip; anchor now 1.03e24
    assertTrue(tripped);

    // After cooldown, a report with no further fast move → shouldReset true.
    vm.warp(block.timestamp + defaultCooldown + 1);
    setMedian(103e22); // flat vs anchor
    bool reset = breaker.shouldReset(rateFeedId);
    assertTrue(reset);
  }

  function test_resetPath_stillMovingFast_doesNotReset() public {
    seed(FIX1);
    assertTrue(moveAfter(30, 103e22)); // trip; anchor 1.03e24

    // Another flash move away from the anchor → shouldReset false.
    vm.warp(block.timestamp + 30);
    setMedian(106e22); // +~2.9% over 30s vs anchor → still too fast
    bool reset = breaker.shouldReset(rateFeedId);
    assertFalse(reset);
  }

  // Scenario 8: anchor updates on every evaluated report.
  function test_anchorUpdatesEachReport() public {
    seed(FIX1);
    moveAfter(100, 1004e21);
    assertEq(breaker.lastMedian(rateFeedId), 1004e21);
    assertEq(breaker.lastReportTime(rateFeedId), block.timestamp);
  }

  // Scenario 9: resetBreakerState re-seeds (next report does not trip).
  function test_resetBreakerState_reseeds() public {
    seed(FIX1);
    breaker.resetBreakerState(rateFeedId);
    assertEq(breaker.lastMedian(rateFeedId), 0);
    assertEq(breaker.lastReportTime(rateFeedId), 0);

    // A would-be flash move now just re-seeds instead of tripping.
    bool tripped = moveAfter(30, 106e22);
    assertFalse(tripped);
    assertEq(breaker.lastMedian(rateFeedId), 106e22);
  }

  // Scenario 10: a slow drift that stays within slew across multiple reports never trips.
  function test_sustainedSlowDriftWithinSlew_neverTrips() public {
    seed(FIX1);
    uint256 m = FIX1;
    for (uint256 i = 0; i < 5; i++) {
      // +0.4% per hour: allowed over 3600s = min(5%, 0.5% + 2%) = 2.5% >> 0.4% → allow.
      m = (m * 1004) / 1000;
      bool tripped = moveAfter(3600, m);
      assertFalse(tripped, "slow drift within slew must not trip");
    }
  }

  // Scenario 11: per-feed override beats the default; an unconfigured feed uses the default.
  function test_perFeedOverride_usedOverDefault() public {
    breaker.setSlewParameters(rateFeedId, CR_BASE, CR_SLEW, CR_MAX);
    (uint256 b, uint256 s, uint256 mx) = breaker.getSlewParameters(rateFeedId);
    assertEq(b, CR_BASE);
    assertEq(s, CR_SLEW);
    assertEq(mx, CR_MAX);

    // otherFeed has no override → default FX params.
    (uint256 b2, uint256 s2, uint256 mx2) = breaker.getSlewParameters(otherFeed);
    assertEq(b2, FX_BASE);
    assertEq(s2, FX_SLEW);
    assertEq(mx2, FX_MAX);

    // With the crypto override, a +6% move over 30s no longer trips (crypto maxJump is 20%, slew higher).
    // baseJump 1% + 30*slew ≈ 1.08%; 6% > that → still trips. Use a move within crypto allowance instead.
    seed(FIX1);
    bool tripped = moveAfter(3600, 105e22); // +5% over 1h; crypto allowed = min(20%, 1%+10%) = 11% → allow
    assertFalse(tripped);
  }
}

contract MedianDeltaBreakerV2Test_admin is MedianDeltaBreakerV2Test {
  function test_onlyBreakerBox_canTrigger() public {
    seed(FIX1);
    setMedian(103e22);
    vm.prank(makeAddr("notBreakerBox"));
    vm.expectRevert(abi.encodeWithSignature("CallerMustBeBreakerBox()"));
    breaker.shouldTrigger(rateFeedId);
  }

  function test_getCooldown_defaultAndOverride() public {
    assertEq(breaker.getCooldown(rateFeedId), defaultCooldown);
    address[] memory feeds = new address[](1);
    feeds[0] = rateFeedId;
    uint256[] memory cds = new uint256[](1);
    cds[0] = 900;
    breaker.setCooldownTimes(feeds, cds);
    assertEq(breaker.getCooldown(rateFeedId), 900);
  }

  function test_setSlewParameters_revertsOnInvalid() public {
    vm.expectRevert(abi.encodeWithSignature("InvalidSlewParameters()"));
    breaker.setSlewParameters(rateFeedId, 2e22, 0, 1e22); // baseJump > maxJump
  }

  function test_setSlewParameters_onlyOwner() public {
    vm.prank(makeAddr("notOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    breaker.setSlewParameters(rateFeedId, FX_BASE, FX_SLEW, FX_MAX);
  }
}
