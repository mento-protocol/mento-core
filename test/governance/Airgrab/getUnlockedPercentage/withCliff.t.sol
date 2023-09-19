// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { GetUnlockedPercentage_Airgrab_Test } from "./Base.t.sol";

contract GetUnlockedPercentage_Cliff_Airgrab_Test is GetUnlockedPercentage_Airgrab_Test {
  /// @notice With only cliff reward as 100%
  function setUp() public override {
    super.setUp();
    basePercentage = 0;
    lockPercentage = 0;
    cliffPercentage = 100e16;
    slopePercentage = 0;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 0;
    initAirgrab();
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_Cliff_Fuzz(uint32 cliff_, uint32 slope_) public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    uint256 pctWithCliff = airgrab.getUnlockedPercentage(0, cliff_);
    require(pctWithCliff <= 100e16, "unlocked should always be < 100%");
    // Slope doesn't influence
    assertEq(airgrab.getUnlockedPercentage(slope_, cliff_), pctWithCliff);
  }

  /// @notice variations of cliff
  function test_GetUnlockedPercentage_Cliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no cliff
    testCases[1] = TestCase(2, 0, 142857142857142857); // fractional cliff
    testCases[2] = TestCase(7, 0, 50e16); // half cliff
    testCases[3] = TestCase(14, 0, 100e16); // full cliff
    testCases[4] = TestCase(20, 0, 100e16); // excede cliff
    run(testCases);
  }
}
