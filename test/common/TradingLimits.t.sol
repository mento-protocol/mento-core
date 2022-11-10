// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { TradingLimits } from "contracts/common/TradingLimits.sol";

// forge test --match-contract TradingLimits -vvv
contract TradingLimitsTest is Test {
    using TradingLimits for TradingLimits.Data;

    uint8 private constant L0 = 1; // 0b001
    uint8 private constant L1 = 2; // 0b010
    uint8 private constant LG = 4; // 0b100

    TradingLimits.Data private tradingLimit;

    function setUp() public {
        TradingLimits.Data memory _tradingLimit;
        tradingLimit = _tradingLimit;
    }

    /* ==================== #configure ==================== */

    function test_configure_whenNothingOn_withL0() public {
        TradingLimits.Data memory config;
        config.timestep0 = 100;
        config.limit0 = 1000;
        config.flags = L0;
        
        tradingLimit = tradingLimit.configure(config);

        assertEq(uint256(tradingLimit.timestep0), 100);
        assertEq(tradingLimit.limit0, 1000);
        assertEq(tradingLimit.lastUpdated0, block.timestamp);

        assertEq(uint256(tradingLimit.timestep1), 0);
        assertEq(tradingLimit.limit1, 0);
        assertEq(uint256(tradingLimit.lastUpdated1), 0);

        assertEq(tradingLimit.limitGlobal, 0);
        assertEq(uint256(tradingLimit.flags), uint256(L0));
    }

    function test_configure_whenNothingOn_withL0L1() public {
        TradingLimits.Data memory config;
        config.timestep0 = 100;
        config.limit0 = 1000;
        config.timestep1 = 1000;
        config.limit1 = 10000;
        config.flags = L0 | L1;

        tradingLimit = tradingLimit.configure(config);

        assertEq(uint256(tradingLimit.timestep0), 100);
        assertEq(tradingLimit.limit0, 1000);
        assertEq(tradingLimit.lastUpdated0, block.timestamp);

        assertEq(uint256(tradingLimit.timestep1), 1000);
        assertEq(tradingLimit.limit1, 10000);
        assertEq(tradingLimit.lastUpdated0, block.timestamp);

        assertEq(tradingLimit.limitGlobal, 0);
        assertEq(uint256(tradingLimit.flags), uint256(L0 | L1));
    }

    function test_configure_whenNothingOn_withL0L1LG() public {
        TradingLimits.Data memory config;
        config.timestep0 = 100;
        config.limit0 = 1000;
        config.timestep1 = 1000;
        config.limit1 = 10000;
        config.limitGlobal = 100000;
        config.flags = L0 | L1 | LG;

        tradingLimit = tradingLimit.configure(config);

        assertEq(uint256(tradingLimit.timestep0), 100);
        assertEq(tradingLimit.limit0, 1000);
        assertEq(tradingLimit.lastUpdated0, block.timestamp);

        assertEq(uint256(tradingLimit.timestep1), 1000);
        assertEq(tradingLimit.limit1, 10000);
        assertEq(tradingLimit.lastUpdated0, block.timestamp);

        assertEq(tradingLimit.limitGlobal, 100000);
        assertEq(uint256(tradingLimit.flags), uint256(L0 | L1 | LG));
    }

    function test_configure_whenL0On_withL0() public {
        TradingLimits.Data memory config0;
        config0.timestep0 = 500;
        config0.limit0 = 1230;
        config0.flags = L0;

        tradingLimit = tradingLimit.configure(config0);

        TradingLimits.Data memory config1;
        config1.timestep0 = 100;
        config1.limit0 = 1000;
        config1.flags = L0;
        
        tradingLimit = tradingLimit.configure(config1);


        assertEq(uint256(tradingLimit.timestep0), 100);
        assertEq(tradingLimit.limit0, 1000);
        assertEq(tradingLimit.lastUpdated0, block.timestamp);

        assertEq(uint256(tradingLimit.timestep1), 0);
        assertEq(tradingLimit.limit1, 0);
        assertEq(uint256(tradingLimit.lastUpdated1), 0);

        assertEq(tradingLimit.limitGlobal, 0);
        assertEq(uint256(tradingLimit.flags), uint256(L0));
    }

    function test_configure_whenL0L1On_withL1LG() public {
        TradingLimits.Data memory config0;
        config0.timestep0 = 500;
        config0.limit0 = 1230;
        config0.timestep1 = 5000;
        config0.limit1 = 1230;
        config0.flags = L0 | L1;

        tradingLimit = tradingLimit.configure(config0);

        TradingLimits.Data memory config1;
        config1.timestep1 = 100;
        config1.limit1 = 1000;
        config1.limitGlobal = 10000;
        config1.flags = L1 | LG;
        
        tradingLimit = tradingLimit.configure(config1);


        assertEq(uint256(tradingLimit.timestep0), 0);
        assertEq(tradingLimit.limit0, 0);
        assertEq(uint256(tradingLimit.lastUpdated0), 0);

        assertEq(uint256(tradingLimit.timestep1), 100);
        assertEq(tradingLimit.limit1, 1000);
        assertEq(uint256(tradingLimit.lastUpdated1), block.timestamp);

        assertEq(tradingLimit.limitGlobal, 10000);
        assertEq(uint256(tradingLimit.flags), uint256(L1 | LG));
    }

    function test_configure_withNetflowOnL0_isLost() public {
        TradingLimits.Data memory config;
        config.timestep0 = 500;
        config.limit0 = 1230;
        config.flags = L0;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow0 = 400;

        tradingLimit = tradingLimit.configure(config);
        assertEq(tradingLimit.netflow0, 0);
    }

    function test_configure_withNetflowOnL1_isLost() public {
        TradingLimits.Data memory config;
        config.timestep1 = 500;
        config.limit1 = 1230;
        config.flags = L1;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow1 = 400;

        tradingLimit = tradingLimit.configure(config);
        assertEq(tradingLimit.netflow1, 0);
    }

    function test_configure_withNetflowOnLG_isKept() public {
        TradingLimits.Data memory config;
        config.limitGlobal = 1230;
        config.flags = LG;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflowGlobal = 400;

        tradingLimit = tradingLimit.configure(config);
        assertEq(tradingLimit.netflowGlobal, 400);
    }

    /* ==================== #configure ==================== */

    function test_isValid_whenNothingOn() public view {
        assert(tradingLimit.isValid());
    }

    function test_isValid_whenL0On_butNotMet() public {
        TradingLimits.Data memory config;
        config.timestep0 = 500;
        config.limit0 = 1230;
        config.flags = L0;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow0 = 500;

        assert(tradingLimit.isValid());
    }

    function test_isValid_whenL0On_andMetPositively() public {
        TradingLimits.Data memory config;
        config.timestep0 = 500;
        config.limit0 = 1230;
        config.flags = L0;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow0 = 1231;

        vm.expectRevert(bytes("L0 Exceeded"));
        tradingLimit.isValid();
    }

    function test_isValid_whenL0On_andMetNegatively() public {
        TradingLimits.Data memory config;
        config.timestep0 = 500;
        config.limit0 = 1230;
        config.flags = L0;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow0 = -1231;

        vm.expectRevert(bytes("L0 Exceeded"));
        tradingLimit.isValid();
    }

    function test_isValid_whenL1On_butNotMet() public {
        TradingLimits.Data memory config;
        config.timestep0 = 500;
        config.limit0 = 1230;
        config.flags = L0;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow0 = 500;

        assert(tradingLimit.isValid());
    }

    function test_isValid_whenL1On_andMetPositively() public {
        TradingLimits.Data memory config;
        config.timestep1 = 500;
        config.limit1 = 1230;
        config.flags = L1;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow1 = 1231;

        vm.expectRevert(bytes("L1 Exceeded"));
        tradingLimit.isValid();
    }

    function test_isValid_whenL1On_andMetNegatively() public {
        TradingLimits.Data memory config;
        config.timestep1 = 500;
        config.limit1 = 1230;
        config.flags = L1;

        tradingLimit = tradingLimit.configure(config);
        tradingLimit.netflow1 = -1231;

        vm.expectRevert(bytes("L1 Exceeded"));
        tradingLimit.isValid();
    }



    function test_whenAllLimitsAreOff_update_doesntUpdateAnything() public {
        tradingLimit = tradingLimit.update(100 * 1e18, 18);
        assertEq(tradingLimit.netflow0, 0);
        assertEq(tradingLimit.netflow1, 0);
        assertEq(tradingLimit.netflowGlobal, 0);
    }

}