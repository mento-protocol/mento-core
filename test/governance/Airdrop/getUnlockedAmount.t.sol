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

  /// @notice With only base as 100%, does not scale down the amount
  function test_GetUnlockedAmount_BaseAt100pc() public {
    basePercentage = 1e18; // 100%
    cliffPercentage = 0;
    slopePercentage = 0;
    initAirdrop();

    amount = 1e18;
    assertEq(subject(), 1e18);
  }

  /// @notice When base:20% cliff:30% slope:50 and tokens are not 
  /// being locked at all, it returns 20% of the claimable amount.
  function test_GetUnlockedAmount_BaseAt20pc() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 50%
    initAirdrop();

    amount = 1e18;
    assertEq(subject(), 2e17); // 20% * 1e18
  }

  /// @notice When base:20% cliff:80% slope:0% and tokens are
  /// getting locked for the full cliff requirement, it 
  /// returns 100% of the claimable amount.
  function test_GetUnlockedAmount_BaseAt20pcAndFullCliff() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 80 * 1e16; // 80%
    slopePercentage = 0;        // 0%
    requiredCliffPeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 14; // -0%
    assertEq(subject(), 1e18);
  }

  /// @notice When base:20% cliff:80% slope:0% and tokens are
  /// getting locked for more than the cliff requirement, it 
  /// returns 100% of the claimable amount.
  function test_GetUnlockedAmount_BaseAt20pcAndMoreThenCliff() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 80 * 1e16; // 80%
    slopePercentage = 0;        // 0%
    requiredCliffPeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 20; // -0%
    assertEq(subject(), 1e18);
  }

  /// @notice When base:20% cliff:80% slope:0% and tokens are
  /// being locked for half of the cliff requirement, it 
  /// returns 60% (= base + 1/2*cliff) of the claimable tokens.
  function test_GetUnlockedAmount_BaseAt20pcAndHalfCliff() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 80 * 1e16; // 80%
    slopePercentage = 0;        // 0%
    requiredCliffPeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 7; // -40%
    assertEq(subject(), 6e17); // 60%
  }

  /// @notice When base:20% cliff:80% slope:0% and tokens are
  /// being locked for 2/14 of the cliff requirement, it 
  /// returns ~31.428% (= base + 2/14*cliff) of the claimable tokens.
  function test_GetUnlockedAmount_BaseAt20pcAndSmallCliff() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 80 * 1e16; // 80%
    slopePercentage = 0;        // 0%
    requiredCliffPeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 2; // -(80/7)%
    assertEq(subject(), 314285714285714285);
  }

  /// @notice When base:20% cliff:30% slope:50% and tokens are
  /// being locked for the full cliff requirement and half of the slope
  /// requirement, it returns 75% (= base + cliff + 1/2 slope) 
  //// of the claimable tokens.
  function test_GetUnlockedAmount_BaseAt20pcFullCliffAndPartialSlope() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 30%
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 14; // -0%
    slope = 7; // -25%
    assertEq(subject(), 75 * 1e16);
  }

  /// @notice When base:20% cliff:30% slope:50% and tokens are
  /// being locked for the full cliff requirement and the full 
  /// slope requirement, it returns 100% of the claimable tokens.
  function test_GetUnlockedAmount_BaseAt20pcFullCliffAndFullSlope() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 30%
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 14; // -0%
    slope = 14; // -0%
    assertEq(subject(), 1e18);
  }

  /// @notice When base:20% cliff:30% slope:50% and tokens are
  /// being locked for more than the cliff requirement and more than
  /// the slope requirement, it returns 100% of the claimable tokens.
  function test_GetUnlockedAmount_BaseAt20pcOverCliffAndOverSlope() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 30%
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 20; // -0%
    slope = 20; // -0%
    assertEq(subject(), 1e18);
  }

  /// @notice When base:20% cliff:30% slope:50% and tokens are
  /// being locked for half of the cliff requirement and half of
  /// the slope requirement, it returns 60% (= base + 1/2 cliff + 1/2 slope)
  // of the claimable tokens;
  function test_GetUnlockedAmount_BaseAt20pcParialCliffParialSlope() public {
    basePercentage = 20 * 1e16;  // 20%
    cliffPercentage = 30 * 1e16; // 30%
    slopePercentage = 50 * 1e16; // 30%
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirdrop();

    amount = 1e18;
    cliff = 7; // -15%
    slope = 7; // -25% 
    assertEq(subject(), 6 * 1e17); // -40%
  }
}
