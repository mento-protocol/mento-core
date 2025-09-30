// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { ITradingLimitsV2 } from "contracts/interfaces/ITradingLimitsV2.sol";

import { TradingLimitsV2Harness } from "test/utils/harnesses/TradingLimitsV2Harness.sol";

// forge test --match-contract TradingLimitsV2 -vvv
contract TradingLimitsV2Test is Test {
  uint8 private constant L0 = 1; // 0b001
  uint8 private constant L1 = 2; // 0b010

  ITradingLimitsV2.State private state;
  TradingLimitsV2Harness private harness;

  function configEmpty() internal pure returns (ITradingLimitsV2.Config memory config) {}

  function configL0(int112 limit0) internal pure returns (ITradingLimitsV2.Config memory config) {
    config.limit0 = limit0;
    config.flags = L0;
  }

  function configL1(int112 limit1) internal pure returns (ITradingLimitsV2.Config memory config) {
    config.limit1 = limit1;
    config.flags = L1;
  }

  function configL0L1(int112 limit0, int112 limit1) internal pure returns (ITradingLimitsV2.Config memory config) {
    config.limit0 = limit0;
    config.limit1 = limit1;
    config.flags = L0 | L1;
  }

  function setUp() public {
    harness = new TradingLimitsV2Harness();
  }

  /* ==================== Config#validate ==================== */

  function test_validate_withL0_isValid() public view {
    ITradingLimitsV2.Config memory config = configL0(1000);
    harness.validate(config);
  }

  function test_validate_withL0_withoutLimit0_isNotValid() public {
    ITradingLimitsV2.Config memory config = configL0(0);
    vm.expectRevert(bytes("limit0 can't be zero if active"));
    harness.validate(config);
  }

  function test_validate_withL0L1_isValid() public view {
    ITradingLimitsV2.Config memory config = configL0L1(1000, 10000);
    harness.validate(config);
  }

  function test_validate_withL1_withoutLimit1_isNotValid() public {
    ITradingLimitsV2.Config memory config = configL0L1(1000, 0);
    vm.expectRevert(bytes("limit1 can't be zero if active"));
    harness.validate(config);
  }

  function test_validate_withL0L1_withLimit0LargerThanLimit1_isNotValid() public {
    ITradingLimitsV2.Config memory config = configL0L1(10000, 1000);
    vm.expectRevert(bytes("limit1 must be greater than limit0"));
    harness.validate(config);
  }

  function test_validate_withL0L1_withEqualLimits_isNotValid() public {
    ITradingLimitsV2.Config memory config = configL0L1(10000, 10000);
    vm.expectRevert(bytes("limit1 must be greater than limit0"));
    harness.validate(config);
  }

  function test_validate_withL1_withoutL0_isValid() public view {
    ITradingLimitsV2.Config memory config = configL1(10000);
    harness.validate(config);
  }

  /* ==================== State#verify ==================== */

  function test_verify_withNoLimits_passes() public view {
    ITradingLimitsV2.Config memory config;
    harness.verify(state, config, 18);
  }

  function test_verify_withL0_withinLimit_passes() public {
    state.netflow0 = 500 * 1e15; // 500 scaled to 15 decimals
    harness.verify(state, configL0(1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withL0_exceedsPositiveLimit_reverts() public {
    state.netflow0 = 1001 * 1e15; // 1001 scaled to 15 decimals
    vm.expectRevert(bytes("L0 Exceeded"));
    harness.verify(state, configL0(1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withL0_exceedsNegativeLimit_reverts() public {
    state.netflow0 = -1001 * 1e15; // -1001 scaled to 15 decimals
    vm.expectRevert(bytes("L0 Exceeded"));
    harness.verify(state, configL0(1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withL1_withinLimit_passes() public {
    state.netflow1 = 500 * 1e15; // 500 scaled to 15 decimals
    harness.verify(state, configL0L1(100 * 1e18, 1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withL1_exceedsPositiveLimit_reverts() public {
    state.netflow1 = 1001 * 1e15; // 1001 scaled to 15 decimals
    vm.expectRevert(bytes("L1 Exceeded"));
    harness.verify(state, configL0L1(100 * 1e18, 1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withL1_exceedsNegativeLimit_reverts() public {
    state.netflow1 = -1001 * 1e15; // -1001 scaled to 15 decimals
    vm.expectRevert(bytes("L1 Exceeded"));
    harness.verify(state, configL0L1(100 * 1e18, 1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withDifferentDecimals_6decimals_passes() public {
    state.netflow0 = 500 * 1e15; // 500 scaled to 15 decimals
    harness.verify(state, configL0(500 * 1e6), 6); // 500 in 6 decimals
  }

  function test_verify_withDifferentDecimals_8decimals_passes() public {
    state.netflow0 = 500 * 1e15; // 500 scaled to 15 decimals
    harness.verify(state, configL0(500 * 1e8), 8); // 500 in 8 decimals
  }

  function test_verify_withDifferentDecimals_24decimals_passes() public {
    state.netflow0 = 500 * 1e15; // 500 scaled to 15 decimals
    harness.verify(state, configL0(500 * 1e24), 24); // 500 in 24 decimals
  }

  function test_verify_withL1Only_withinLimit_passes() public {
    state.netflow1 = 500 * 1e15; // 500 scaled to 15 decimals
    harness.verify(state, configL1(1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withL1Only_exceedsPositiveLimit_reverts() public {
    state.netflow1 = 1001 * 1e15; // 1001 scaled to 15 decimals
    vm.expectRevert(bytes("L1 Exceeded"));
    harness.verify(state, configL1(1000 * 1e18), 18); // 1000 in 18 decimals
  }

  function test_verify_withL1Only_exceedsNegativeLimit_reverts() public {
    state.netflow1 = -1001 * 1e15; // -1001 scaled to 15 decimals
    vm.expectRevert(bytes("L1 Exceeded"));
    harness.verify(state, configL1(1000 * 1e18), 18); // 1000 in 18 decimals
  }

  /* ==================== State#reset ==================== */

  function test_reset_clearsCheckpoints() public {
    state.lastUpdated0 = 123412412;
    state.lastUpdated1 = 123124412;
    state = harness.reset(state, configL0(1000));

    assertEq(uint256(state.lastUpdated0), 0);
    assertEq(uint256(state.lastUpdated1), 0);
  }

  function test_reset_resetsNetflowsOnDisabled() public {
    state.netflow1 = 12312;
    state = harness.reset(state, configL0(1000));

    assertEq(state.netflow1, 0);
  }

  function test_reset_keepsNetflowsOnEnabled() public {
    state.netflow0 = 12312;
    state.netflow1 = 12312;
    state = harness.reset(state, configL0L1(1000, 10000));

    assertEq(state.netflow0, 12312);
    assertEq(state.netflow1, 12312);
  }

  function test_reset_keepsL0_resetsL1_whenOnlyL0Enabled() public {
    state.netflow0 = 12312;
    state.netflow1 = 12312;
    state = harness.reset(state, configL0(1000));

    assertEq(state.netflow0, 12312);
    assertEq(state.netflow1, 0);
  }

  /* ==================== State#update ==================== */

  function test_update_withNoLimit_doesNotUpdate() public {
    state = harness.update(state, configEmpty(), 100 * 1e18, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
  }

  function test_update_withZeroDeltaFlow_doesNotUpdate() public {
    state = harness.update(state, configL0L1(1000, 10000), 0, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
  }

  function test_update_withL0_updatesActive() public {
    state = harness.update(state, configL0(1000 * 1e18), 100 * 1e18, 18);
    assertEq(state.netflow0, 100 * 1e15); // Scaled to 15 decimals
    assertEq(state.netflow1, 0);
  }

  function test_update_withL0L1_updatesActive() public {
    state = harness.update(state, configL0L1(1000 * 1e18, 10000 * 1e18), 100 * 1e18, 18);
    assertEq(state.netflow0, 100 * 1e15); // Scaled to 15 decimals
    assertEq(state.netflow1, 100 * 1e15); // Scaled to 15 decimals
  }

  function test_update_withL1Only_updatesL1() public {
    state = harness.update(state, configL1(10000 * 1e18), 100 * 1e18, 18);
    assertEq(state.netflow0, 0); // L0 not active
    assertEq(state.netflow1, 100 * 1e15); // L1 should be updated
  }

  function test_update_withSmallAmount_doesNotRoundUp() public {
    // In V2, small amounts that scale to 0 are ignored (no rounding)
    state = harness.update(state, configL0(1000 * 1e18), 1, 18); // 1 wei (positive)
    assertEq(state.netflow0, 0); // Should be 0 (too small to register)

    state = ITradingLimitsV2.State(0, 0, 0, 0); // reset
    state = harness.update(state, configL0(1000 * 1e18), -1, 18); // -1 wei (negative)
    assertEq(state.netflow0, 0); // Should be 0 (too small to register)
  }

  function test_update_withSmallAmount_nonZero_updates() public {
    state = harness.update(state, configL0(1000 * 1e18), 1e4, 18); // 0.0001 tokens = 1e14 scaled
    assertEq(state.netflow0, 10); // 1e4 / 1e3 = 10 when scaled from 18 to 15 decimals
  }

  function test_update_resetsL0_after5Minutes() public {
    vm.warp(1000);
    state = harness.update(state, configL0(1000 * 1e18), 100 * 1e18, 18);
    assertEq(state.netflow0, 100 * 1e15);
    assertEq(state.lastUpdated0, 1000);

    // Move forward 5 minutes + 1 second
    vm.warp(1000 + 5 * 60 + 1);
    state = harness.update(state, configL0(1000 * 1e18), 50 * 1e18, 18);

    assertEq(state.netflow0, 50 * 1e15); // Should be reset to just new amount
    assertEq(state.lastUpdated0, 1000 + 5 * 60 + 1);
  }

  function test_update_resetsL1_after1Day() public {
    // Start with a time that allows initial L1 timestamp to be set
    vm.warp(1 days + 1000);
    state = harness.update(state, configL0L1(1000 * 1e18, 10000 * 1e18), 100 * 1e18, 18);
    assertEq(state.netflow1, 100 * 1e15);
    assertEq(state.lastUpdated1, 1 days + 1000);

    // Move forward 1 day + 1 second
    vm.warp(1 days + 1000 + 1 days + 1);
    state = harness.update(state, configL0L1(1000 * 1e18, 10000 * 1e18), 50 * 1e18, 18);

    // Both L0 and L1 should be reset since both timeframes elapsed
    assertEq(state.netflow0, 50 * 1e15); // Should be reset to just new amount
    assertEq(state.netflow1, 50 * 1e15); // Should be reset to just new amount
    assertEq(state.lastUpdated0, 1 days + 1000 + 1 days + 1);
    assertEq(state.lastUpdated1, 1 days + 1000 + 1 days + 1);
  }

  function test_update_accumulatesWithinTimeWindow() public {
    vm.warp(1000);
    state = harness.update(state, configL0(1000 * 1e18), 100 * 1e18, 18);

    // Move forward less than 5 minutes
    vm.warp(1000 + 4 * 60);
    state = harness.update(state, configL0(1000 * 1e18), 50 * 1e18, 18);

    assertEq(state.netflow0, 150 * 1e15); // Should accumulate
  }

  function test_update_L1Only_resetsAfter1Day() public {
    // Test that L1 resets after 1 day when used without L0
    vm.warp(1 days + 1000);
    state = harness.update(state, configL1(10000 * 1e18), 100 * 1e18, 18);
    assertEq(state.netflow1, 100 * 1e15);
    assertEq(state.lastUpdated1, 1 days + 1000);

    // Move forward 1 day + 1 second
    vm.warp(1 days + 1000 + 1 days + 1);
    state = harness.update(state, configL1(10000 * 1e18), 50 * 1e18, 18);

    // L1 should be reset
    assertEq(state.netflow1, 50 * 1e15); // Should be reset to just new amount
    assertEq(state.lastUpdated1, 1 days + 1000 + 1 days + 1);
    assertEq(state.netflow0, 0); // L0 should remain 0
  }

  function test_update_L1Only_accumulatesWithinTimeWindow() public {
    vm.warp(1000);
    state = harness.update(state, configL1(10000 * 1e18), 100 * 1e18, 18);

    // Move forward less than 1 day
    vm.warp(1000 + 12 hours);
    state = harness.update(state, configL1(10000 * 1e18), 50 * 1e18, 18);

    assertEq(state.netflow1, 150 * 1e15); // Should accumulate
    assertEq(state.netflow0, 0); // L0 should remain 0
  }

  /* ==================== Scaling Functions ==================== */

  function test_scaleValue_with18Decimals_scalesDown() public view {
    int96 scaled = harness.scaleValue(100 * 1e18, 18);
    assertEq(scaled, 100 * 1e15);
  }

  function test_scaleValue_with15Decimals_noScaling() public view {
    int96 scaled = harness.scaleValue(100 * 1e15, 15);
    assertEq(scaled, 100 * 1e15);
  }

  function test_scaleValue_with6Decimals_scalesUp() public view {
    int96 scaled = harness.scaleValue(100 * 1e6, 6);
    assertEq(scaled, 100 * 1e15);
  }

  function test_scaleValue_withZero_returnsZero() public view {
    int96 scaled = harness.scaleValue(0, 18);
    assertEq(scaled, 0);
  }

  function test_scaleValue_withNegative_scalesCorrectly() public view {
    int96 scaled = harness.scaleValue(-100 * 1e18, 18);
    assertEq(scaled, -100 * 1e15);
  }

  function test_scaleValue_withMaxInt96_reverts() public {
    int256 tooLarge = int256(type(int96).max) + 1;
    vm.expectRevert(bytes("Flow exceeds int96 bounds"));
    harness.scaleValue(tooLarge, 15);
  }

  function test_scaleValue_withMinInt96_reverts() public {
    int256 tooSmall = int256(type(int96).min) - 1;
    vm.expectRevert(bytes("Flow exceeds int96 bounds"));
    harness.scaleValue(tooSmall, 15);
  }

  function test_scaleValue_asLimit_with18Decimals_scalesDown() public view {
    int96 scaled = harness.scaleValue(100 * 1e18, 18);
    assertEq(scaled, 100 * 1e15);
  }

  function test_scaleValue_asLimit_with15Decimals_noScaling() public view {
    int96 scaled = harness.scaleValue(100 * 1e15, 15);
    assertEq(scaled, 100 * 1e15);
  }

  function test_scaleValue_asLimit_with6Decimals_scalesUp() public view {
    int96 scaled = harness.scaleValue(100 * 1e6, 6);
    assertEq(scaled, 100 * 1e15);
  }

  function test_scaleValue_asLimit_withZero_returnsZero() public view {
    int96 scaled = harness.scaleValue(0, 18);
    assertEq(scaled, 0);
  }

  function test_scaleValue_asLimit_withMaxInt96_reverts() public {
    int256 tooLarge = int256(type(int96).max) + 1;
    vm.expectRevert(bytes("Flow exceeds int96 bounds"));
    harness.scaleValue(tooLarge, 15);
  }

  /* ==================== SafeAdd ==================== */

  function test_safeAdd_withNormalValues_works() public view {
    int96 result = harness.safeAdd(100, 200);
    assertEq(result, 300);
  }

  function test_safeAdd_withNegativeValues_works() public view {
    int96 result = harness.safeAdd(-100, -200);
    assertEq(result, -300);
  }

  function test_safeAdd_withZero_works() public view {
    int96 result = harness.safeAdd(100, 0);
    assertEq(result, 100);
  }

  function test_safeAdd_withOverflow_reverts() public {
    vm.expectRevert(bytes("int96 addition overflow"));
    harness.safeAdd(type(int96).max, 1);
  }

  function test_safeAdd_withUnderflow_reverts() public {
    vm.expectRevert(bytes("int96 addition overflow"));
    harness.safeAdd(type(int96).min, -1);
  }

  /* ==================== Integration Tests ==================== */

  function test_integration_fullWorkflow_18decimals() public {
    ITradingLimitsV2.Config memory config = configL0L1(1000 * 1e18, 10000 * 1e18);

    // Validate config
    harness.validate(config);

    // Update with some flow
    vm.warp(1000);
    state = harness.update(state, config, 500 * 1e18, 18);

    // Verify within limits
    harness.verify(state, config, 18);

    // Update more and verify still within limits
    state = harness.update(state, config, 400 * 1e18, 18);
    harness.verify(state, config, 18);

    // Update to exceed L0 limit
    state = harness.update(state, config, 200 * 1e18, 18);
    vm.expectRevert(bytes("L0 Exceeded"));
    harness.verify(state, config, 18);
  }

  function test_integration_fullWorkflow_6decimals() public {
    ITradingLimitsV2.Config memory config = configL0L1(1000 * 1e6, 10000 * 1e6);

    // Validate config
    harness.validate(config);

    // Update with some flow
    vm.warp(1000);
    state = harness.update(state, config, 500 * 1e6, 6);

    // Verify within limits
    harness.verify(state, config, 6);

    // Check scaled values are correct
    assertEq(state.netflow0, 500 * 1e15); // Should be scaled to 15 decimals
  }

  function test_integration_timeWindowReset_L0and_L1() public {
    ITradingLimitsV2.Config memory config = configL0L1(1000 * 1e18, 10000 * 1e18);

    vm.warp(1000);

    // Fill L0 limit
    state = harness.update(state, config, 1000 * 1e18, 18);
    harness.verify(state, config, 18);

    // Move forward 5 minutes to reset L0 but not L1
    vm.warp(1000 + 5 * 60 + 1);

    // Should be able to add more to L0 (reset) but L1 accumulates
    state = harness.update(state, config, 1000 * 1e18, 18);
    harness.verify(state, config, 18);

    // Now L1 should have 2000, L0 should have 1000
    assertEq(state.netflow0, 1000 * 1e15);
    assertEq(state.netflow1, 2000 * 1e15);

    // Move forward 1 day to reset L1
    vm.warp(1000 + 1 days + 1);

    state = harness.update(state, config, 1000 * 1e18, 18);

    // Both should be reset to just the new amount
    assertEq(state.netflow0, 1000 * 1e15);
    assertEq(state.netflow1, 1000 * 1e15);
  }

  function test_integration_fullWorkflow_L1Only() public {
    ITradingLimitsV2.Config memory config = configL1(10000 * 1e18);

    // Validate config (should pass now)
    harness.validate(config);

    // Update with some flow
    vm.warp(1000);
    state = harness.update(state, config, 5000 * 1e18, 18);

    // Verify within limits
    harness.verify(state, config, 18);
    assertEq(state.netflow0, 0); // L0 not active
    assertEq(state.netflow1, 5000 * 1e15); // L1 active

    // Update more and verify still within limits
    state = harness.update(state, config, 4000 * 1e18, 18);
    harness.verify(state, config, 18);
    assertEq(state.netflow1, 9000 * 1e15);

    // Update to exceed L1 limit
    state = harness.update(state, config, 2000 * 1e18, 18);
    vm.expectRevert(bytes("L1 Exceeded"));
    harness.verify(state, config, 18);

    // Move forward 1 day to reset L1
    vm.warp(1000 + 1 days + 1);
    state = harness.update(state, config, 5000 * 1e18, 18);

    // L1 should be reset to just the new amount
    assertEq(state.netflow1, 5000 * 1e15);
    harness.verify(state, config, 18); // Should pass
  }
}
