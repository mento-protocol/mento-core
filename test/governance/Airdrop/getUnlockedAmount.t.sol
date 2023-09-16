// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airdrop_Test } from "./Base.t.sol";

contract GetUnlockedAmount_Airdrop_Test is Airdrop_Test {
  uint256 amount;
  uint32 slope;
  uint32 cliff;

  function subject() internal view returns (uint256) {
    return airdrop.getUnlockedAmount(amount, slope, cliff);
  }

  function test_GetUnlockedAmount_BaseAt100pc() public {
    basePercentage = 1e18; // 100%
    cliffPercentage = 0;
    slopePercentage = 0;
    setAirdrop();

    amount = 1e18;
    assertEq(subject(), 1e18);
  }

  function test_GetUnlockedAmount_BaseAt20pc() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 50%
    setAirdrop();

    amount = 1e18;
    assertEq(subject(), 2e17);
  }

  function test_GetUnlockedAmount_BaseAt20pcAndFullCliff() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 80 * 1e16; // 80%
    slopePercentage = 0;        // 0%
    requiredCliffPeriod = 14;
    setAirdrop();

    amount = 1e18;
    cliff = 14; // -0%
    assertEq(subject(), 1e18);
  }

  function test_GetUnlockedAmount_BaseAt20pcAndHalfCliff() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 80 * 1e16; // 80%
    slopePercentage = 0;        // 0%
    requiredCliffPeriod = 14;
    setAirdrop();

    amount = 1e18;
    cliff = 7; // -40%
    assertEq(subject(), 6e17);
  }

  function test_GetUnlockedAmount_BaseAt20pcAndSmallCliff() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 80 * 1e16; // 80%
    slopePercentage = 0;        // 0%
    requiredCliffPeriod = 14;
    setAirdrop();

    amount = 1e18;
    cliff = 2; // -(80/7)%
    assertEq(subject(), 314285714285714285);
  }

  function test_GetUnlockedAmount_BaseAt20pcFullCliffAndPartialSlope() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 30%
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    setAirdrop();

    amount = 1e18;
    cliff = 14; // -0%
    slope = 7; // -25%
    assertEq(subject(), 75 * 1e16);
  }

  function test_GetUnlockedAmount_BaseAt20pcFullCliffAndFullSlope() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 30%
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    setAirdrop();

    amount = 1e18;
    cliff = 14; // -0%
    slope = 14; // -0%
    assertEq(subject(), 1e18);
  }

  function test_GetUnlockedAmount_BaseAt20pcParialCliffParialSlope() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 30%
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    setAirdrop();

    amount = 1e18;
    cliff = 7; // -15%
    slope = 7; // -25% 
    assertEq(subject(), 6 * 1e17); // -40%
  }
}
