// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { GetUnlockedPercentage_Airgrab_Test } from "./Base.t.sol";

contract GetUnlockedPercentage_Slope_Airgrab_Test is GetUnlockedPercentage_Airgrab_Test {
  /// @notice With only slope reward as 100%
  function setUp() override public {
    super.setUp();
    basePercentage      = 0;
    lockPercentage      = 0;
    cliffPercentage     = 0;
    slopePercentage     = 100e16; // 100%
    requiredSlopePeriod = 0;
    requiredSlopePeriod = 14; // weeks ~= 3 months
    initAirgrab();
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_Slope_Fuzz(uint32 cliff_, uint32 slope_) public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    uint256 pctWithSlope = airgrab.getUnlockedPercentage(slope_, 0);
    require(pctWithSlope <= 100e16, "unlocked should always be < 100%");
    // Slope doesn't influence
    assertEq(airgrab.getUnlockedPercentage(slope_, cliff_), pctWithSlope);
  }

  /// @notice variations of slope
  function test_GetUnlockedPercentage_Slope() public {
    TestCase[] memory testCases = new TestCase[](5);
    //---------------------| Cliff | Slope | Expected %         |
    testCases[0] = TestCase( 0,      0,      0                  ); // no slope
    testCases[1] = TestCase( 0,      2,      142857142857142857 ); // fractional slope
    testCases[2] = TestCase( 0,      7,      50e16              ); // half slope
    testCases[3] = TestCase( 0,      14,     100e16             ); // full slope
    testCases[4] = TestCase( 0,      20,     100e16             ); // excede slope
    run(testCases);
  }
}

