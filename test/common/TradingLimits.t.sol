// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { TradingLimits } from "contracts/common/TradingLimits.sol";

// forge test --match-contract TradingLimits -vvv
contract TradingLimitsTest is Test {
    using TradingLimits for TradingLimits.State;
    using TradingLimits for TradingLimits.Config;

    uint8 private constant L0 = 1; // 0b001
    uint8 private constant L1 = 2; // 0b010
    uint8 private constant LG = 4; // 0b100

    TradingLimits.State private state;

    function setUp() public {
        TradingLimits.State memory _state;
        state = _state;
    }

    function configEmpty() internal pure returns(TradingLimits.Config memory config) {}

    function configL0(
        uint32 timestep0,
        int48 limit0
    ) internal pure returns (TradingLimits.Config memory config) {
        config.timestep0 = timestep0;
        config.limit0 = limit0;
        config.flags = L0;
    }

    function configL1(
        uint32 timestep1,
        int48 limit1
    ) internal pure returns (TradingLimits.Config memory config) {
        config.timestep1 = timestep1;
        config.limit1 = limit1;
        config.flags = L1;
    }

    function configLG(
        int48 limitGlobal
    ) internal pure returns (TradingLimits.Config memory config) {
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

    function test_validate_withL0_verify() public {
        TradingLimits.Config memory config = configL0(100, 1000);
        assertEq(config.validate(), true);
    }

    function test_validate_withL0_withoutTimestep_isNotValid() public {
        TradingLimits.Config memory config = configL0(0, 1000);
        vm.expectRevert(bytes("timestep0 can't be zero if active"));
        config.validate();
    }

    function test_validate_withL0L1_isValid() public {
        TradingLimits.Config memory config = configL0L1(100, 1000, 1000, 10000);
        assertEq(config.validate(), true);
    }

    function test_validate_withL0L1_withoutTimestape_isNotValid() public {
        TradingLimits.Config memory config = configL0L1(0, 1000, 1000, 10000);
        vm.expectRevert(bytes("timestep0 can't be zero if active"));
        config.validate();
    }

    function test_validate_withL0L1LG_isValid() public {
        TradingLimits.Config memory config = configL0L1LG(100, 1000, 1000, 10000, 100000);
        assertEq(config.validate(), true);
    }

    function test_configure_withL1LG_isNotValid() public {
        TradingLimits.Config memory config = configL1LG(1000, 10000, 100000);
        vm.expectRevert(bytes("L1 without L0 not allowed"));
        config.validate();
    }

    /* ==================== State#verify ==================== */

    function test_verify_withNothingOn() public view {
        TradingLimits.Config memory config;
        assert(state.verify(config));
    }

    function test_verify_withL0_butNotMet() public {
        state.netflow0 = 500;
        assert(state.verify(configL0(500, 1230)));
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
        assert(state.verify(configL0L1(50, 100, 500, 1230)));
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
        assert(state.verify(configLG(1230)));
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

    /* ==================== #update ==================== */

    function test_update_withNoLimit_updatesOnlyGlobal() public {
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
}