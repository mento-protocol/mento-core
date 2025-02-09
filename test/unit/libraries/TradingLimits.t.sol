// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { TradingLimitsHarness } from "test/utils/harnesses/TradingLimitsHarness.sol";

// forge test --match-contract TradingLimits -vvv
contract TradingLimitsTest is Test {
  uint8 private constant L0 = 1; // 0b001
  uint8 private constant L1 = 2; // 0b010
  uint8 private constant LG = 4; // 0b100

  ITradingLimits.State private state;
  TradingLimitsHarness private harness;

  function configEmpty() internal pure returns (ITradingLimits.Config memory config) {}

  function configL0(uint32 timestep0, int48 limit0) internal pure returns (ITradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.flags = L0;
  }

  function configL1(uint32 timestep1, int48 limit1) internal pure returns (ITradingLimits.Config memory config) {
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.flags = L1;
  }

  function configLG(int48 limitGlobal) internal pure returns (ITradingLimits.Config memory config) {
    config.limitGlobal = limitGlobal;
    config.flags = LG;
  }

  function configL0L1(
    uint32 timestep0,
    int48 limit0,
    uint32 timestep1,
    int48 limit1
  ) internal pure returns (ITradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.flags = L0 | L1;
  }

  function configL0L1LG(
    uint32 timestep0,
    int48 limit0,
    uint32 timestep1,
    int48 limit1,
    int48 limitGlobal
  ) internal pure returns (ITradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.limitGlobal = limitGlobal;
    config.flags = L0 | L1 | LG;
  }

  function configL1LG(
    uint32 timestep1,
    int48 limit1,
    int48 limitGlobal
  ) internal pure returns (ITradingLimits.Config memory config) {
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.limitGlobal = limitGlobal;
    config.flags = L1 | LG;
  }

  function configL0LG(
    uint32 timestep0,
    int48 limit0,
    int48 limitGlobal
  ) internal pure returns (ITradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.limitGlobal = limitGlobal;
    config.flags = L0 | LG;
  }

  function setUp() public {
    harness = new TradingLimitsHarness();
  }

  /* ==================== Config#validate ==================== */

  function test_validate_withL0_isValid() public view {
    ITradingLimits.Config memory config = configL0(100, 1000);
    harness.validate(config);
  }

  function test_validate_withL0_withoutTimestep_isNotValid() public {
    ITradingLimits.Config memory config = configL0(0, 1000);
    vm.expectRevert("timestep0 can't be zero if active");
    harness.validate(config);
  }

  function test_validate_withL0_withoutLimit0_isNotValid() public {
    ITradingLimits.Config memory config = configL0(100, 0);
    vm.expectRevert("limit0 can't be zero if active");
    harness.validate(config);
  }

  function test_validate_withL0L1_isValid() public view {
    ITradingLimits.Config memory config = configL0L1(100, 1000, 1000, 10000);
    harness.validate(config);
  }

  function test_validate_withL1_withoutLimit1_isNotValid() public {
    ITradingLimits.Config memory config = configL0L1(100, 1000, 1000, 0);
    vm.expectRevert("limit1 can't be zero if active");
    harness.validate(config);
  }

  function test_validate_withL0L1_withoutTimestape_isNotValid() public {
    ITradingLimits.Config memory config = configL0L1(0, 1000, 1000, 10000);
    vm.expectRevert("timestep0 can't be zero if active");
    harness.validate(config);
  }

  function test_validate_withL0L1_withLimit0LargerLimit1_isNotValid() public {
    ITradingLimits.Config memory config = configL0L1(10000, 10000, 1000, 1000);
    vm.expectRevert("limit1 must be greater than limit0");
    harness.validate(config);
  }

  function test_validate_withLG_withoutLimitGlobal_isNotValid() public {
    ITradingLimits.Config memory config = configL0L1LG(100, 1000, 1000, 10000, 0);
    vm.expectRevert("limitGlobal can't be zero if active");
    harness.validate(config);
  }

  function test_validate_withL0LG_withLimit0LargerLimitGlobal_isNotValid() public {
    ITradingLimits.Config memory config = configL0LG(10000, 10000, 1000);
    vm.expectRevert("limitGlobal must be greater than limit0");
    harness.validate(config);
  }

  function test_validate_withL1LG_withLimit1LargerLimitGlobal_isNotValid() public {
    ITradingLimits.Config memory config = configL0L1LG(100, 1000, 10000, 10000, 1000);
    vm.expectRevert("limitGlobal must be greater than limit1");
    harness.validate(config);
  }

  function test_validate_withL0L1LG_isValid() public view {
    ITradingLimits.Config memory config = configL0L1LG(100, 1000, 1000, 10000, 100000);
    harness.validate(config);
  }

  function test_configure_withL1LG_isNotValid() public {
    ITradingLimits.Config memory config = configL1LG(1000, 10000, 100000);
    vm.expectRevert("L1 without L0 not allowed");
    harness.validate(config);
  }

  /* ==================== State#reset ==================== */

  function test_reset_clearsCheckpoints() public {
    state.lastUpdated0 = 123412412;
    state.lastUpdated1 = 123124412;
    state = harness.reset(state, configL0(500, 1000));

    assertEq(uint256(state.lastUpdated0), 0);
    assertEq(uint256(state.lastUpdated1), 0);
  }

  function test_reset_resetsNetflowsOnDisabled() public {
    state.netflow1 = 12312;
    state.netflowGlobal = 12312;
    state = harness.reset(state, configL0(500, 1000));

    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
  }

  function test_reset_keepsNetflowsOnEnabled() public {
    state.netflow0 = 12312;
    state.netflow1 = 12312;
    state.netflowGlobal = 12312;
    state = harness.reset(state, configL0LG(500, 1000, 100000));

    assertEq(state.netflow0, 12312);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 12312);
  }

  function test_reset_withL0LGDisabled_resetsNetflowDecimals() public {
    state.netflowDecimals = 1e14 * 0.1;
    state = harness.reset(state, configEmpty());
    assertEq(state.netflowDecimals, 0);
  }

  /* ==================== State#verify ==================== */

  function test_verify_withNothingOn() public view {
    ITradingLimits.Config memory config;
    harness.verify(state, config);
  }

  function test_verify_withL0_butNotMet() public {
    state.netflow0 = 500;
    harness.verify(state, configL0(500, 1230));
  }

  function test_verify_withL0_andMetPositively() public {
    state.netflow0 = 1231;
    vm.expectRevert("L0 Exceeded");
    harness.verify(state, configL0(500, 1230));
  }

  function test_verify_withL0_andMetNegatively() public {
    state.netflow0 = -1231;
    vm.expectRevert("L0 Exceeded");
    harness.verify(state, configL0(500, 1230));
  }

  function test_verify_withL0L1_butNoneMet() public {
    state.netflow1 = 500;
    harness.verify(state, configL0L1(50, 100, 500, 1230));
  }

  function test_verify_withL0L1_andL1MetPositively() public {
    state.netflow1 = 1231;
    vm.expectRevert("L1 Exceeded");
    harness.verify(state, configL0L1(50, 100, 500, 1230));
  }

  function test_verify_withL0L1_andL1MetNegatively() public {
    state.netflow1 = -1231;
    vm.expectRevert("L1 Exceeded");
    harness.verify(state, configL0L1(50, 100, 500, 1230));
  }

  function test_verify_withLG_butNoneMet() public {
    state.netflowGlobal = 500;
    harness.verify(state, configLG(1230));
  }

  function test_verify_withLG_andMetPositively() public {
    state.netflowGlobal = 1231;
    vm.expectRevert("LG Exceeded");
    harness.verify(state, configLG(1230));
  }

  function test_verify_withLG_andMetNegatively() public {
    state.netflowGlobal = -1231;
    vm.expectRevert("LG Exceeded");
    harness.verify(state, configLG(1230));
  }

  function test_verify_withL0_takesDecimalsIntoAccount() public {
    state.netflow0 = 1230;
    state.netflowDecimals = 0;
    // 1230 + 0.0 <= 1230 -> no revert
    harness.verify(state, configL0(500, 1230));

    state.netflow0 = -1230;
    state.netflowDecimals = -1e14 * 0.1;
    // -1230 - 0.1 < -1230 -> revert
    vm.expectRevert("L0 Exceeded");
    harness.verify(state, configL0(500, 1230));

    state.netflow0 = 1230;
    state.netflowDecimals = 1e14 * 0.1;
    // 1230 + 0.1 <= 1230 -> revert
    vm.expectRevert("L0 Exceeded");
    harness.verify(state, configL0(500, 1230));
  }

  function test_verify_withL1_takesDecimalsIntoAccount() public {
    state.netflow1 = 1230;
    state.netflowDecimals = 0;
    // 1230 + 0.0 <= 1230 -> no revert
    harness.verify(state, configL1(500, 1230));

    state.netflow1 = -1230;
    state.netflowDecimals = -1e14 * 0.1;
    // -1230 - 0.1 < -1230 -> revert
    vm.expectRevert("L1 Exceeded");
    harness.verify(state, configL1(500, 1230));

    state.netflow1 = 1230;
    state.netflowDecimals = 1e14 * 0.1;
    // 1230 + 0.1 <= 1230 -> revert
    vm.expectRevert("L1 Exceeded");
    harness.verify(state, configL1(500, 1230));
  }

  function test_verify_withLG_takesDecimalsIntoAccount() public {
    state.netflowGlobal = 1230;
    state.netflowDecimals = 0;
    // 1230 + 0.0 <= 1230 -> no revert
    harness.verify(state, configLG(1230));

    state.netflowGlobal = -1230;
    state.netflowDecimals = -1e14 * 0.1;
    // -1230 - 0.1 < -1230 -> revert
    vm.expectRevert("LG Exceeded");
    harness.verify(state, configLG(1230));

    state.netflowGlobal = 1230;
    state.netflowDecimals = 1e14 * 0.1;
    // 1230 + 0.1 <= 1230 -> revert
    vm.expectRevert("LG Exceeded");
    harness.verify(state, configLG(1230));
  }

  /* ==================== State#update ==================== */

  function test_update_withNoLimit_doesNotUpdate() public {
    state = harness.update(state, configEmpty(), 100 * 1e18, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
  }

  function test_update_withZeroDeltaFlow_doesNotUpdate() public {
    state = harness.update(state, configL0L1LG(300, 1000, 1 days, 10000, 1000000), 0, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
  }

  function test_update_withL0_updatesActive() public {
    state = harness.update(state, configL0(500, 1000), 100 * 1e18, 18);
    assertEq(state.netflow0, 100);
    assertEq(state.netflowGlobal, 0);
  }

  function test_update_withL0L1_updatesActive() public {
    state = harness.update(state, configL0L1(500, 1000, 5000, 500000), 100 * 1e18, 18);
    assertEq(state.netflow0, 100);
    assertEq(state.netflow1, 100);
    assertEq(state.netflowGlobal, 0);
  }

  function test_update_withL0LG_updatesActive() public {
    state = harness.update(state, configL0LG(500, 1000, 500000), 100 * 1e18, 18);
    assertEq(state.netflow0, 100);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 100);
  }

  function test_update_withLG_updatesActive() public {
    state = harness.update(state, configLG(500000), 100 * 1e18, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 100);
  }

  function test_update_withTooLargeAmount_reverts() public {
    vm.expectRevert("dFlow too large");
    state = harness.update(state, configLG(500000), 3 * 10e32, 18);
  }

  function test_update_withTooSmallAmount_reverts() public {
    int256 tooSmall = (type(int48).min - int256(1)) * 1e18;
    vm.expectRevert("dFlow too small");
    state = harness.update(state, configLG(500000), tooSmall, 18);
  }

  function test_update_withOverflowOnAdd_reverts() public {
    ITradingLimits.Config memory config = configLG(int48(uint48(2 ** 47)));
    int256 maxFlow = int256(type(int48).max);

    state = harness.update(state, config, (maxFlow - 1000) * 1e18, 18);
    state = harness.update(state, config, 1000 * 1e18, 18);

    vm.expectRevert("int48 addition overflow");
    state = harness.update(state, config, 1 * 1e18, 18);
  }

  function test_update_withUnderflowOnAdd_reverts() public {
    ITradingLimits.Config memory config = configLG(int48(uint48(2 ** 47)));
    int256 minFlow = int256(type(int48).min);

    state = harness.update(state, config, (minFlow + 1000) * 1e18, 18);
    state = harness.update(state, config, -1000 * 1e18, 18);

    vm.expectRevert("int48 addition overflow");
    state = harness.update(state, config, -1 * 1e18, 18);
  }

  function test_update_whenL0AndTimestep0_resetsNetFlowDecimals() public {
    uint32 timestep0 = 5 minutes;
    state.netflowDecimals = 1e14 * 0.1;

    vm.warp(block.timestamp + timestep0 + 1);

    state = harness.update(state, configL0(timestep0, 1000), 100 * 1e18, 18);
    assertEq(state.netflowDecimals, 0);
  }

  function test_update_withPositiveDecimalsLessThan1e4_updatesAs0() public {
    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), 1e4 * 0.9999, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
    assertEq(state.netflowDecimals, 0);

    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), 12345, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
    assertEq(state.netflowDecimals, 1);
  }

  function test_update_withPositiveAmountsAndDecimals_updatesNetflowAndDecimals() public {
    // state before netflowDecimals = 0.2
    state.netflowDecimals = 0.2 * 1e14;
    state.netflow0 = 1; // 1.2
    state.netflow1 = -100; // -100 + 0.2 = -99.8
    state.netflowGlobal = 1000; // 1000.2

    ITradingLimits.State memory stateBefore = state;

    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), 10.6 * 1e18, 18);

    // state after netflowDecimals = netflowDecimalsBefore + 0.6
    assertEq(state.netflowDecimals, stateBefore.netflowDecimals + 0.6 * 1e14);

    // state after netflow = netflowBefore + 10
    assertEq(state.netflow0, stateBefore.netflow0 + 10);
    assertEq(state.netflow1, stateBefore.netflow1 + 10);
    assertEq(state.netflowGlobal, stateBefore.netflowGlobal + 10);
  }

  function test_update_withPositiveCarryOver_updatesNetflowAndDecimals() public {
    // state before netflowDecimals = 0.3
    state.netflowDecimals = 0.3 * 1e14;
    state.netflow0 = 1; // 1.3
    state.netflow1 = -100; // -100 + 0.3 = -99.7
    state.netflowGlobal = 1000; // 1000.3

    ITradingLimits.State memory stateBefore = state;

    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), 10.8 * 1e18, 18);

    // state after netflowDecimals = netflowDecimalsBefore + 0.8 = 0.3 + 0.8 = 1.1 -> 0.1 & 1 carry
    assertEq(state.netflowDecimals, 0.1 * 1e14);

    // state after netflow = netflowBefore + 10 + carry = netflowBefore + 11
    assertEq(state.netflow0, stateBefore.netflow0 + 11);
    assertEq(state.netflow1, stateBefore.netflow1 + 11);
    assertEq(state.netflowGlobal, stateBefore.netflowGlobal + 11);
  }

  function test_update_withNegativeDecimalsLessThan1e4_updatesAs0() public {
    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), -1e4 * 0.9999, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
    assertEq(state.netflowDecimals, 0);

    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), -12345, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
    assertEq(state.netflowDecimals, -1);
  }

  function test_update_withNegativeAmountsAndDecimals_updatesNetflowAndDecimals() public {
    // state before netflowDecimals = -0.2
    state.netflowDecimals = -0.2 * 1e14;
    state.netflow0 = -1; // -1.2
    state.netflow1 = 100; // 100 - 0.2 = 99.8
    state.netflowGlobal = -1000; // -1000.2

    ITradingLimits.State memory stateBefore = state;

    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), -10.6 * 1e18, 18);

    // state after netflowDecimals = netflowDecimalsBefore - 0.6
    assertEq(state.netflowDecimals, stateBefore.netflowDecimals - 0.6 * 1e14);

    // state after netflow = netflowBefore - 10
    assertEq(state.netflow0, stateBefore.netflow0 - 10);
    assertEq(state.netflow1, stateBefore.netflow1 - 10);
    assertEq(state.netflowGlobal, stateBefore.netflowGlobal - 10);
  }

  function test_update_withNegativeCarryOver_updatesNetflowAndDecimals() public {
    // state before netflowDecimals = -0.3
    state.netflowDecimals = -0.3 * 1e14;
    state.netflow0 = -1; // -1.3
    state.netflow1 = 100; // 100 - 0.3 = 99.7
    state.netflowGlobal = -1000; // -1000.3

    ITradingLimits.State memory stateBefore = state;

    state = harness.update(state, configL0L1LG(300, 1000, 86400, 100_000, 1_000_000), -10.8 * 1e18, 18);

    // state after netflowDecimals = netflowDecimalsBefore - 0.8 = -0.3 - 0.8 = -1.1 -> -0.1 & -1 carry
    assertEq(state.netflowDecimals, -0.1 * 1e14);

    // state after netflow = netflowBefore - 10 + carry = netflowBefore - 11
    assertEq(state.netflow0, stateBefore.netflow0 - 11);
    assertEq(state.netflow1, stateBefore.netflow1 - 11);
    assertEq(state.netflowGlobal, stateBefore.netflowGlobal - 11);
  }
}
