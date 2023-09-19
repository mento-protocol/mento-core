// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { GetUnlockedPercentage_Airgrab_Test } from "../Base.t.sol";

contract GetUnlockedPercentage_LockCliffSlope_Airgrab_Test is GetUnlockedPercentage_Airgrab_Test {
  /// @notice With base reward as 20% and cliff reward as 100%
  function setUp() public virtual override {
    super.setUp();
    basePercentage = 0;
    lockPercentage = 10e16;
    cliffPercentage = 40e16;
    slopePercentage = 50e16;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 14;
    initAirgrab();
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_LockCliffSlope_Fuzz(uint32 cliff_, uint32 slope_) public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice no cliff and varitations of slope
  function test_GetUnlockedPercentage_LockCliffSlope_NoCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no slope
    testCases[1] = TestCase(0, 2, 171428571428571428); // fractional slope
    testCases[2] = TestCase(0, 7, 35e16); // half slope
    testCases[3] = TestCase(0, 14, 60e16); // full slope
    testCases[4] = TestCase(0, 20, 60e16); // excede slope
    run(testCases);
  }

  /// @notice fractional cliff and variation on slope
  function test_GetUnlockedPercentage_LockCliffSlope_FractionalCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(2, 0, 157142857142857142); // no slope
    testCases[1] = TestCase(2, 2, 228571428571428570); // fractional slope
    testCases[2] = TestCase(2, 7, 407142857142857142); // half slope
    testCases[3] = TestCase(2, 14, 657142857142857142); // full slope
    testCases[4] = TestCase(2, 20, 657142857142857142); // excede slope
    run(testCases);
  }

  /// @notice half cliff and variations of slope
  function test_GetUnlockedPercentage_LockCliffSlope_HalfCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(7, 0, 30e16); // no slope
    testCases[1] = TestCase(7, 2, 371428571428571428); // fractional slope
    testCases[2] = TestCase(7, 7, 55e16); // half slope
    testCases[3] = TestCase(7, 14, 80e16); // full slope
    testCases[4] = TestCase(7, 20, 80e16); // excede slope
    run(testCases);
  }

  /// @notice full cliff and variations of slope
  function test_GetUnlockedPercentage_LockCliffSlope_FullCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(14, 0, 50e16); // no slope
    testCases[1] = TestCase(14, 2, 571428571428571428); // fractional slope
    testCases[2] = TestCase(14, 7, 75e16); // half slope
    testCases[3] = TestCase(14, 14, 100e16); // full slope
    testCases[4] = TestCase(14, 20, 100e16); // excede slope
    run(testCases);
  }

  /// @notice exceed cliff and variations of slope
  function test_GetUnlockedPercentage_LockCliffSlope_ExceedCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(20, 0, 50e16); // no slope
    testCases[1] = TestCase(20, 2, 571428571428571428); // fractional slope
    testCases[2] = TestCase(20, 7, 75e16); // half slope
    testCases[3] = TestCase(20, 14, 100e16); // full slope
    testCases[4] = TestCase(20, 20, 100e16); // excede slope
    run(testCases);
  }
}
