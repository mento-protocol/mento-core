// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { GetUnlockedPercentage_Airgrab_Test } from "../Base.t.sol";

contract GetUnlockedPercentage_BaseLockCliffSlope_Airgrab_Test is GetUnlockedPercentage_Airgrab_Test {
  /// @notice With base reward as 20% and cliff reward as 100%
  function setUp() public virtual override {
    super.setUp();
    basePercentage = 10e16;
    lockPercentage = 10e16;
    cliffPercentage = 30e16;
    slopePercentage = 50e16;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 14;
    initAirgrab();
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_Fuzz(uint32 cliff_, uint32 slope_) public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice no cliff and varitations of slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_NoCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    //---------------------| Cliff | Slope | Expected %         |
    testCases[0] = TestCase(0, 0, 10e16); // no slope
    testCases[1] = TestCase(0, 2, 271428571428571428); // fractional slope
    testCases[2] = TestCase(0, 7, 45e16); // half slope
    testCases[3] = TestCase(0, 14, 70e16); // full slope
    testCases[4] = TestCase(0, 20, 70e16); // excede slope
    run(testCases);
  }

  /// @notice fractional cliff and variation on slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_FractionalCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    //---------------------| Cliff | Slope | Expected %         |
    testCases[0] = TestCase(2, 0, 242857142857142857); // no slope
    testCases[1] = TestCase(2, 2, 314285714285714285); // fractional slope
    testCases[2] = TestCase(2, 7, 492857142857142857); // half slope
    testCases[3] = TestCase(2, 14, 742857142857142857); // full slope
    testCases[4] = TestCase(2, 20, 742857142857142857); // excede slope
    run(testCases);
  }

  /// @notice half cliff and variations of slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_HalfCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    //---------------------| Cliff | Slope | Expected %         |
    testCases[0] = TestCase(7, 0, 35e16); // no slope
    testCases[1] = TestCase(7, 2, 421428571428571428); // fractional slope
    testCases[2] = TestCase(7, 7, 60e16); // half slope
    testCases[3] = TestCase(7, 14, 85e16); // full slope
    testCases[4] = TestCase(7, 20, 85e16); // excede slope
    run(testCases);
  }

  /// @notice full cliff and variations of slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_FullCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    //---------------------| Cliff | Slope | Expected %         |
    testCases[0] = TestCase(14, 0, 50e16); // no slope
    testCases[1] = TestCase(14, 2, 571428571428571428); // fractional slope
    testCases[2] = TestCase(14, 7, 75e16); // half slope
    testCases[3] = TestCase(14, 14, 100e16); // full slope
    testCases[4] = TestCase(14, 20, 100e16); // excede slope
    run(testCases);
  }

  /// @notice exceed cliff and variations of slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_ExceedCliff() public {
    TestCase[] memory testCases = new TestCase[](5);
    //---------------------| Cliff | Slope | Expected %         |
    testCases[0] = TestCase(14, 0, 50e16); // no slope
    testCases[1] = TestCase(14, 2, 571428571428571428); // fractional slope
    testCases[2] = TestCase(14, 7, 75e16); // half slope
    testCases[3] = TestCase(14, 14, 100e16); // full slope
    testCases[4] = TestCase(14, 20, 100e16); // excede slope
    run(testCases);
  }
}
