// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test } from "celo-foundry/Test.sol";
import { console } from "forge-std/console.sol";
import { TradingLimits } from "contracts/libraries/TradingLimits.sol";

// forge test --match-contract TradingLimits -vvv
contract TradingLimitsTest is Test {
  using TradingLimits for TradingLimits.State;
  using TradingLimits for TradingLimits.Config;

  uint8 private constant L0 = 1; // 0b001
  uint8 private constant L1 = 2; // 0b010
  uint8 private constant LG = 4; // 0b100

  TradingLimits.State private state;

  function configEmpty() internal pure returns (TradingLimits.Config memory config) {}

  function configL0(uint32 timestep0, int48 limit0) internal pure returns (TradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.flags = L0;
  }

  function configL1(uint32 timestep1, int48 limit1) internal pure returns (TradingLimits.Config memory config) {
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.flags = L1;
  }

  function configLG(int48 limitGlobal) internal pure returns (TradingLimits.Config memory config) {
    config.limitGlobal = limitGlobal;
    config.flags = LG;
  }

  function configL0L1(
    uint32 timestep0,
    int48 limit0,
    uint32 timestep1,
    int48 limit1
  ) internal pure returns (TradingLimits.Config memory config) {
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
  ) internal pure returns (TradingLimits.Config memory config) {
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
  ) internal pure returns (TradingLimits.Config memory config) {
    config.timestep1 = timestep1;
    config.limit1 = limit1;
    config.limitGlobal = limitGlobal;
    config.flags = L1 | LG;
  }

  function configL0LG(
    uint32 timestep0,
    int48 limit0,
    int48 limitGlobal
  ) internal pure returns (TradingLimits.Config memory config) {
    config.timestep0 = timestep0;
    config.limit0 = limit0;
    config.limitGlobal = limitGlobal;
    config.flags = L0 | LG;
  }

  /* ==================== Config#validate ==================== */

  function test_validate_withL0_isValid() public pure {
    TradingLimits.Config memory config = configL0(100, 1000);
    config.validate();
  }

  function test_validate_withL0_withoutTimestep_isNotValid() public {
    TradingLimits.Config memory config = configL0(0, 1000);
    vm.expectRevert(bytes("timestep0 can't be zero if active"));
    config.validate();
  }

  function test_validate_withL0_withoutLimit0_isNotValid() public {
    TradingLimits.Config memory config = configL0(100, 0);
    vm.expectRevert(bytes("limit0 can't be zero if active"));
    config.validate();
  }

  function test_validate_withL0L1_isValid() public pure {
    TradingLimits.Config memory config = configL0L1(100, 1000, 1000, 10000);
    config.validate();
  }

  function test_validate_withL1_withoutLimit1_isNotValid() public {
    TradingLimits.Config memory config = configL0L1(100, 1000, 1000, 0);
    vm.expectRevert(bytes("limit1 can't be zero if active"));
    config.validate();
  }

  function test_validate_withL0L1_withoutTimestape_isNotValid() public {
    TradingLimits.Config memory config = configL0L1(0, 1000, 1000, 10000);
    vm.expectRevert(bytes("timestep0 can't be zero if active"));
    config.validate();
  }

  function test_validate_withL0L1_withLimit0LargerLimit1_isNotValid() public {
    TradingLimits.Config memory config = configL0L1(10000, 10000, 1000, 1000);
    vm.expectRevert(bytes("limit1 must be greater than limit0"));
    config.validate();
  }

  function test_validate_withLG_withoutLimitGlobal_isNotValid() public {
    TradingLimits.Config memory config = configL0L1LG(100, 1000, 1000, 10000, 0);
    vm.expectRevert(bytes("limitGlobal can't be zero if active"));
    config.validate();
  }

  function test_validate_withL0LG_withLimit0LargerLimitGlobal_isNotValid() public {
    TradingLimits.Config memory config = configL0LG(10000, 10000, 1000);
    vm.expectRevert(bytes("limitGlobal must be greater than limit0"));
    config.validate();
  }

  function test_validate_withL1LG_withLimit1LargerLimitGlobal_isNotValid() public {
    TradingLimits.Config memory config = configL0L1LG(100, 1000, 10000, 10000, 1000);
    vm.expectRevert(bytes("limitGlobal must be greater than limit1"));
    config.validate();
  }

  function test_validate_withL0L1LG_isValid() public pure {
    TradingLimits.Config memory config = configL0L1LG(100, 1000, 1000, 10000, 100000);
    config.validate();
  }

  function test_configure_withL1LG_isNotValid() public {
    TradingLimits.Config memory config = configL1LG(1000, 10000, 100000);
    vm.expectRevert(bytes("L1 without L0 not allowed"));
    config.validate();
  }

  /* ==================== State#reset ==================== */

  function test_reset_clearsCheckpoints() public {
    state.lastUpdated0 = 123412412;
    state.lastUpdated1 = 123124412;
    state = state.reset(configL0(500, 1000));

    assertEq(uint256(state.lastUpdated0), 0);
    assertEq(uint256(state.lastUpdated1), 0);
  }

  function test_reset_resetsNetflowsOnDisabled() public {
    state.netflow1 = 12312;
    state.netflowGlobal = 12312;
    state = state.reset(configL0(500, 1000));

    assertEq(uint256(state.netflow1), 0);
    assertEq(uint256(state.netflowGlobal), 0);
  }

  function test_reset_keepsNetflowsOnEnabled() public {
    state.netflow0 = 12312;
    state.netflow1 = 12312;
    state.netflowGlobal = 12312;
    state = state.reset(configL0LG(500, 1000, 100000));

    assertEq(uint256(state.netflow0), 12312);
    assertEq(uint256(state.netflow1), 0);
    assertEq(uint256(state.netflowGlobal), 12312);
  }

  /* ==================== State#verify ==================== */

  function test_verify_withNothingOn() public view {
    TradingLimits.Config memory config;
    state.verify(config);
  }

  function test_verify_withL0_butNotMet() public {
    state.netflow0 = 500;
    state.verify(configL0(500, 1230));
  }

  function test_verify_withL0_andMetPositively() public {
    state.netflow0 = 1231;
    vm.expectRevert(bytes("L0 Exceeded"));
    state.verify(configL0(500, 1230));
  }

  function test_verify_withL0_andMetNegatively() public {
    state.netflow0 = -1231;
    vm.expectRevert(bytes("L0 Exceeded"));
    state.verify(configL0(500, 1230));
  }

  function test_verify_withL0L1_butNoneMet() public {
    state.netflow1 = 500;
    state.verify(configL0L1(50, 100, 500, 1230));
  }

  function test_verify_withL0L1_andL1MetPositively() public {
    state.netflow1 = 1231;
    vm.expectRevert(bytes("L1 Exceeded"));
    state.verify(configL0L1(50, 100, 500, 1230));
  }

  function test_verify_withL0L1_andL1MetNegatively() public {
    state.netflow1 = -1231;
    vm.expectRevert(bytes("L1 Exceeded"));
    state.verify(configL0L1(50, 100, 500, 1230));
  }

  function test_verify_withLG_butNoneMet() public {
    state.netflowGlobal = 500;
    state.verify(configLG(1230));
  }

  function test_verify_withLG_andMetPositively() public {
    state.netflowGlobal = 1231;
    vm.expectRevert(bytes("LG Exceeded"));
    state.verify(configLG(1230));
  }

  function test_verify_withLG_andMetNegatively() public {
    state.netflowGlobal = -1231;
    vm.expectRevert(bytes("LG Exceeded"));
    state.verify(configLG(1230));
  }

  /* ==================== State#update ==================== */

  function test_update_withNoLimit_doesNotUpdate() public {
    state = state.update(configEmpty(), 100 * 1e18, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 0);
  }

  function test_update_withL0_updatesActive() public {
    state = state.update(configL0(500, 1000), 100 * 1e18, 18);
    assertEq(state.netflow0, 100);
    assertEq(state.netflowGlobal, 0);
  }

  function test_update_withL0L1_updatesActive() public {
    state = state.update(configL0L1(500, 1000, 5000, 500000), 100 * 1e18, 18);
    assertEq(state.netflow0, 100);
    assertEq(state.netflow1, 100);
    assertEq(state.netflowGlobal, 0);
  }

  function test_update_withL0LG_updatesActive() public {
    state = state.update(configL0LG(500, 1000, 500000), 100 * 1e18, 18);
    assertEq(state.netflow0, 100);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 100);
  }

  function test_update_withLG_updatesActive() public {
    state = state.update(configLG(500000), 100 * 1e18, 18);
    assertEq(state.netflow0, 0);
    assertEq(state.netflow1, 0);
    assertEq(state.netflowGlobal, 100);
  }

  function test_update_withSubUnitAmounts_updatesAs1() public {
    state = state.update(configLG(500000), 1e6, 18);
    assertEq(state.netflowGlobal, 1);
  }

  function test_update_withTooLargeAmount_reverts() public {
    vm.expectRevert(bytes("dFlow too large"));
    state = state.update(configLG(500000), 3 * 10e32, 18);
  }

  function test_update_withOverflowOnAdd_reverts() public {
    TradingLimits.Config memory config = configLG(int48(2**47));
    int256 maxFlow = int256(uint48(-1) / 2);

    state = state.update(config, (maxFlow - 1000) * 1e18, 18);
    vm.expectRevert(bytes("int48 addition overflow"));
    state = state.update(config, 1002 * 10e18, 18);
  }
}
