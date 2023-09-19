// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { GetUnlockedPercentage_Airgrab_Test } from "../Base.t.sol";

contract GetUnlockedPercentage_BaseLock_Airgrab_Test is GetUnlockedPercentage_Airgrab_Test {
  function setUp() override public {
    super.setUp();
    basePercentage      = 50e16;
    lockPercentage      = 50e16;
    cliffPercentage     = 0;
    slopePercentage     = 0;
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirgrab();
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseLock_Fuzz(uint32 cliff_, uint32 slope_) public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice variatons of lock
  function test_GetUnlockedPercentage_BaseLock() public {
    TestCase[] memory testCases = new TestCase[](4);
    //---------------------| Cliff | Slope | Expected % |
    testCases[0] = TestCase( 0,      0,      50e16      ); // no lock
    testCases[1] = TestCase( 1,      0,      100e16     ); // cliff lock
    testCases[2] = TestCase( 0,      1,      100e16     ); // slope lock
    testCases[3] = TestCase( 1,      1,      100e16     ); // both
    run(testCases);
  }
}

