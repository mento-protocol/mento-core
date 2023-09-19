// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { GetUnlockedPercentage_Airgrab_Test } from "../Base.t.sol";

contract GetUnlockedPercentage_Base_Airgrab_Test is GetUnlockedPercentage_Airgrab_Test {
  function setUp() public override {
    super.setUp();
    basePercentage = 100e16;
    lockPercentage = 0;
    cliffPercentage = 0;
    slopePercentage = 0;
    requiredCliffPeriod = 0;
    requiredSlopePeriod = 0;
    initAirgrab();
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_Base_Fuzz(uint32 cliff_, uint32 slope_) public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice variatons of lock
  function test_GetUnlockedPercentage_Base() public {
    TestCase[] memory testCases = new TestCase[](4);
    //---------------------| Cliff | Slope | Expected % |
    testCases[0] = TestCase(0, 0, 100e16); // no lock
    testCases[1] = TestCase(1, 0, 100e16); // cliff lock
    testCases[2] = TestCase(0, 1, 100e16); // slope lock
    testCases[3] = TestCase(1, 1, 100e16); // both
    run(testCases);
  }
}
