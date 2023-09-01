// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import { console } from "forge-std-next/console.sol";
import { Test } from "forge-std-next/Test.sol";

import { MentoToken } from "contracts/tokens/MentoToken.sol";

contract MentoTokenTest is Test {
    MentoToken mentoToken;

    address constant VESTING_CONTRACT = address(111);
    address constant AIRGRAB_CONTRACT = address(222);
    address constant TREASURY_CONTRACT = address(333);
    address constant EMISSION_CONTRACT = address(444);

    address constant ALICE = address(9999);
    address constant BOB = address(8888);

    uint256 constant INITIAL_TOTAL_SUPPLY = 1_000_000_000 * 1e18;


    function setUp() public {
        mentoToken = new MentoToken(VESTING_CONTRACT, AIRGRAB_CONTRACT, TREASURY_CONTRACT, EMISSION_CONTRACT);
    }

    function test_constructor_shouldMintCorrectAmounts() public {

        uint256 vestingAmount = mentoToken.balanceOf(VESTING_CONTRACT);
        uint256 airgrabAmount = mentoToken.balanceOf(AIRGRAB_CONTRACT);
        uint256 treasuryAmount = mentoToken.balanceOf(TREASURY_CONTRACT);
        uint256 emissionAmount = mentoToken.balanceOf(EMISSION_CONTRACT);
        
        assertEq(vestingAmount, 200_000_000 * 1e18);
        assertEq(airgrabAmount, 50_000_000 * 1e18);
        assertEq(treasuryAmount, 100_000_000 * 1e18);
        assertEq(emissionAmount, 650_000_000 * 1e18);
        
        assertEq(vestingAmount + airgrabAmount + treasuryAmount + emissionAmount, INITIAL_TOTAL_SUPPLY);
        assertEq(mentoToken.totalSupply(), INITIAL_TOTAL_SUPPLY);

    }
}