// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airgrab_Base_Test } from "./Base.t.sol";
import { console } from "forge-std-next/console.sol";

contract GetUnlockedPercentage_Airgrab_Test is Airgrab_Base_Test {
  struct TestCase {
    uint32 cliff;
    uint32 slope;
    uint256 expected;
  }

  /// @notice Run all testcases
  /// @param cases The testcases
  function run(TestCase[] memory cases) public {
    for (uint256 i = 0; i < cases.length; i++) {
      TestCase memory c = cases[i];
      uint256 actual = airgrab.getUnlockedPercentage(c.slope, c.cliff);
      if (actual != c.expected) {
        console.log(unicode"❌ Test Case: (cliff:%s, slope:%s) = %s ", c.cliff, c.slope, c.expected);
      } else {
        console.log(unicode"✅ Test Case: (cliff:%s, slope:%s) = %s", c.cliff, c.slope, c.expected);
      }
      assertEq(actual, c.expected);
    }
  }

  // ======================================
  // with: Cliff
  // without: Base Lock Slope
  // ======================================

  /// @notice With only cliff reward as 100%
  modifier c_setUp() {
    basePercentage = 0;
    lockPercentage = 0;
    cliffPercentage = 100e16;
    slopePercentage = 0;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 0;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_Cliff_Fuzz(uint32 cliff, uint32 slope) c_setUp public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);
    uint256 pctWithCliff = airgrab.getUnlockedPercentage(0, cliff);
    require(pctWithCliff <= 100e16, "unlocked should always be < 100%");
    // Slope doesn't influence
    assertEq(airgrab.getUnlockedPercentage(slope, cliff), pctWithCliff);
  }

  /// @notice variations of cliff
  function test_GetUnlockedPercentage_Cliff() c_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no cliff
    testCases[1] = TestCase(2, 0, 142857142857142857); // fractional cliff
    testCases[2] = TestCase(7, 0, 50e16); // half cliff
    testCases[3] = TestCase(14, 0, 100e16); // full cliff
    testCases[4] = TestCase(20, 0, 100e16); // excede cliff
    run(testCases);
  }

  // ======================================
  // with: Slope
  // without: Base Lock Cliff
  // ======================================

  /// @notice With only slope reward as 100%
  modifier s_setUp() {
    basePercentage = 0;
    lockPercentage = 0;
    cliffPercentage = 0;
    slopePercentage = 100e16; // 100%
    requiredSlopePeriod = 0;
    requiredSlopePeriod = 14; // weeks ~= 3 months
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_Slope_Fuzz(uint32 cliff, uint32 slope) s_setUp public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);
    uint256 pctWithSlope = airgrab.getUnlockedPercentage(slope, 0);
    require(pctWithSlope <= 100e16, "unlocked should always be < 100%");
    // Slope doesn't influence
    assertEq(airgrab.getUnlockedPercentage(slope, cliff), pctWithSlope);
  }

  /// @notice variations of slope
  function test_GetUnlockedPercentage_Slope() s_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no slope
    testCases[1] = TestCase(0, 2, 142857142857142857); // fractional slope
    testCases[2] = TestCase(0, 7, 50e16); // half slope
    testCases[3] = TestCase(0, 14, 100e16); // full slope
    testCases[4] = TestCase(0, 20, 100e16); // excede slope
    run(testCases);
  }

  // ======================================
  // with: Cliff Slope
  // without: Base Lock
  // ======================================

  /// @notice With base reward as 20% and cliff reward as 100%
  modifier cs_setUp() {
    basePercentage = 0;
    lockPercentage = 0;
    cliffPercentage = 40e16;
    slopePercentage = 60e16;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 14;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_CliffSlope_Fuzz(uint32 cliff, uint32 slope) cs_setUp public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope, cliff) <= 100e16);
  }

  /// @notice no cliff and varitations of slope
  function test_GetUnlockedPercentage_CliffSlope_NoCliff() cs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no slope
    testCases[1] = TestCase(0, 2, 85714285714285714); // fractional slope
    testCases[2] = TestCase(0, 7, 30e16); // half slope
    testCases[3] = TestCase(0, 14, 60e16); // full slope
    testCases[4] = TestCase(0, 20, 60e16); // excede slope
    run(testCases);
  }

  /// @notice fractional cliff and variation on slope
  function test_GetUnlockedPercentage_CliffSlope_FractionalCliff() cs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(2, 0, 57142857142857142); // no slope
    testCases[1] = TestCase(2, 2, 142857142857142856); // fractional slope
    testCases[2] = TestCase(2, 7, 357142857142857142); // half slope
    testCases[3] = TestCase(2, 14, 657142857142857142); // full slope
    testCases[4] = TestCase(2, 20, 657142857142857142); // excede slope
    run(testCases);
  }

  /// @notice half cliff and variations of slope
  function test_GetUnlockedPercentage_CliffSlope_HalfCliff() cs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(7, 0, 20e16); // no slope
    testCases[1] = TestCase(7, 2, 285714285714285714); // fractional slope
    testCases[2] = TestCase(7, 7, 50e16); // half slope
    testCases[3] = TestCase(7, 14, 80e16); // full slope
    testCases[4] = TestCase(7, 20, 80e16); // excede slope
    run(testCases);
  }

  /// @notice full cliff and variations of slope
  function test_GetUnlockedPercentage_CliffSlope_FullCliff() cs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(14, 0, 40e16); // no slope
    testCases[1] = TestCase(14, 2, 485714285714285714); // fractional slope
    testCases[2] = TestCase(14, 7, 70e16); // half slope
    testCases[3] = TestCase(14, 14, 100e16); // full slope
    testCases[4] = TestCase(14, 20, 100e16); // excede slope
    run(testCases);
  }

  /// @notice exceed cliff and variations of slope
  function test_GetUnlockedPercentage_CliffSlope_ExceedCliff() cs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(20, 0, 40e16); // no slope
    testCases[1] = TestCase(20, 2, 485714285714285714); // fractional slope
    testCases[2] = TestCase(20, 7, 70e16); // half slope
    testCases[3] = TestCase(20, 14, 100e16); // full slope
    testCases[4] = TestCase(20, 20, 100e16); // excede slope
    run(testCases);
  }

  // ======================================
  // with: Lock
  // without: Base Cliff Slope
  // ======================================

  /// @notice With lock reward as 100%
  modifier l_setUp() {
    basePercentage = 0;
    lockPercentage = 100e16;
    cliffPercentage = 0;
    slopePercentage = 0;
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_Lock_Fuzz(uint32 cliff, uint32 slope) l_setUp public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope, cliff) <= 100e16);
  }

  /// @notice variatons of lock
  function test_GetUnlockedPercentage_Lock() l_setUp public {
    TestCase[] memory testCases = new TestCase[](4);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no lock
    testCases[1] = TestCase(1, 0, 100e16); // cliff lock
    testCases[2] = TestCase(0, 1, 100e16); // slope lock
    testCases[3] = TestCase(1, 1, 100e16); // both
    run(testCases);
  }

  // ======================================
  // with: Lock Cliff
  // without: Base Slope
  // ======================================

  /// @notice With lock at 10% and cliff reward at 90%
  modifier lc_setUp() {
    basePercentage = 0;
    lockPercentage = 10e16;
    cliffPercentage = 90e16;
    slopePercentage = 0;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 0;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_LockCliff_Fuzz(uint32 cliff, uint32 slope) lc_setUp public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);
    uint256 pctWithCliff = airgrab.getUnlockedPercentage(0, cliff);
    require(pctWithCliff <= 100e16, "unlocked should always be < 100%");
    if (cliff > 0) {
      // Slope doesn't influence
      assertEq(airgrab.getUnlockedPercentage(slope, cliff), pctWithCliff);
    } else if (slope > 0) {
      // Slopes opens unlock
      require(airgrab.getUnlockedPercentage(slope, cliff) > pctWithCliff, "unlocked should increase");
    }
  }

  /// @notice variations of cliff
  function test_GetUnlockedPercentage_LockCliff() lc_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no cliff
    testCases[1] = TestCase(2, 0, 228571428571428571); // fractional cliff
    testCases[2] = TestCase(7, 0, 55e16); // half cliff
    testCases[3] = TestCase(14, 0, 100e16); // full cliff
    testCases[4] = TestCase(20, 0, 100e16); // excede cliff
    run(testCases);
  }

  // ======================================
  // with: Lock Slope
  // without: Base Cliff
  // ======================================

  /// @notice With lock at 20%, slope reward at 80%
  modifier ls_setUp() {
    basePercentage = 0;
    lockPercentage = 20e16;
    cliffPercentage = 0;
    slopePercentage = 80e16;
    requiredSlopePeriod = 0;
    requiredSlopePeriod = 14; // weeks ~= 3 months
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_LockSlope_Fuzz(uint32 cliff, uint32 slope) ls_setUp public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);
    uint256 pctWithSlope = airgrab.getUnlockedPercentage(slope, 0);
    require(pctWithSlope <= 100e16, "unlocked should always be < 100%");
    if (slope > 0) {
      // Cliff doesn't influence
      assertEq(airgrab.getUnlockedPercentage(slope, cliff), pctWithSlope);
    } else if (cliff > 0) {
      // Cliff opens unlock
      require(airgrab.getUnlockedPercentage(slope, cliff) > pctWithSlope, "unlocked should increase");
    }
  }

  /// @notice variations of slope
  function test_GetUnlockedPercentage_LockSlope() ls_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 0); // no slope
    testCases[1] = TestCase(0, 2, 314285714285714285); // fractional slope
    testCases[2] = TestCase(0, 7, 60e16); // half slope
    testCases[3] = TestCase(0, 14, 100e16); // full slope
    testCases[4] = TestCase(0, 20, 100e16); // excede slope
    run(testCases);
  }

  // ======================================
  // with: Lock Cliff Slope
  // without: Base
  // ======================================

  /// @notice With lock reward at 20%, cliff reward at 40% and slope reward at 40%
  modifier lcs_setUp() {
    basePercentage = 0;
    lockPercentage = 10e16;
    cliffPercentage = 40e16;
    slopePercentage = 50e16;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 14;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_LockCliffslopeFuzz(uint32 cliff, uint32 slope) lcs_setUp public {
    vm.assume(cliff <= MAX_CLIFF_PERIOD);
    vm.assume(slope <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope, cliff) <= 100e16);
  }

  /// @notice no cliff and varitations of slope
  function test_GetUnlockedPercentage_LockCliffslopeNoCliff() lcs_setUp public {
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
  function test_GetUnlockedPercentage_LockCliffslopeFractionalCliff() lcs_setUp public {
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
  function test_GetUnlockedPercentage_LockCliffslopeHalfCliff() lcs_setUp public {
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
  function test_GetUnlockedPercentage_LockCliffslopeFullCliff() lcs_setUp public {
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
  function test_GetUnlockedPercentage_LockCliffslopeExceedCliff() lcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(20, 0, 50e16); // no slope
    testCases[1] = TestCase(20, 2, 571428571428571428); // fractional slope
    testCases[2] = TestCase(20, 7, 75e16); // half slope
    testCases[3] = TestCase(20, 14, 100e16); // full slope
    testCases[4] = TestCase(20, 20, 100e16); // excede slope
    run(testCases);
  }

  // ======================================
  // with: Base
  // without: Lock Cliff Slope
  // ======================================

  /// @notice With base reward at 100%
  modifier b_setUp() {
    basePercentage = 100e16;
    lockPercentage = 0;
    cliffPercentage = 0;
    slopePercentage = 0;
    requiredCliffPeriod = 0;
    requiredSlopePeriod = 0;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_Base_Fuzz(uint32 cliff_, uint32 slope_) b_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice variatons of lock
  function test_GetUnlockedPercentage_Base() b_setUp public {
    TestCase[] memory testCases = new TestCase[](4);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 100e16); // no lock
    testCases[1] = TestCase(1, 0, 100e16); // cliff lock
    testCases[2] = TestCase(0, 1, 100e16); // slope lock
    testCases[3] = TestCase(1, 1, 100e16); // both
    run(testCases);
  }

  // ======================================
  // with: Base Cliff
  // without: Lock Slope
  // ======================================

  /// @notice With base reward at 20% and cliff reward at 80%
  modifier bc_setUp() {
    basePercentage = 20e16; // 20%
    lockPercentage = 0;
    cliffPercentage = 80e16; // 80%
    slopePercentage = 0;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 0;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseCliff_Fuzz(uint32 cliff_, uint32 slope_) bc_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    uint256 pctWithCliff = airgrab.getUnlockedPercentage(0, cliff_);
    require(pctWithCliff <= 100e16, "unlocked should always be < 100%");
    // Slope doesn't influence
    assertEq(airgrab.getUnlockedPercentage(slope_, cliff_), pctWithCliff);
  }

  /// @notice variations of cliff
  function test_GetUnlockedPercentage_BaseCliff() bc_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    //---------------------| Cliff | Slope | Expected %         |
    testCases[0] = TestCase(0, 0, 20e16); // no cliff
    testCases[1] = TestCase(2, 0, 314285714285714285); // fractional cliff
    testCases[2] = TestCase(7, 0, 60e16); // half cliff
    testCases[3] = TestCase(14, 0, 100e16); // full cliff
    testCases[4] = TestCase(20, 0, 100e16); // excede cliff
    run(testCases);
  }

  // ======================================
  // with: Base Slope
  // without: Lock Cliff
  // ======================================

  /// @notice With base reward at 20% and slope reward at 80%
  modifier bs_setUp() {
    basePercentage = 20e16;
    lockPercentage = 0;
    cliffPercentage = 0;
    slopePercentage = 80e16;
    requiredSlopePeriod = 0;
    requiredSlopePeriod = 14; // weeks ~= 3 months
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseSlope_Fuzz(uint32 cliff_, uint32 slope_) bs_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    uint256 pctWithSlope = airgrab.getUnlockedPercentage(slope_, 0);
    require(pctWithSlope <= 100e16, "unlocked should always be < 100%");
    // Slope doesn't influence
    assertEq(airgrab.getUnlockedPercentage(slope_, cliff_), pctWithSlope);
  }

  /// @notice variations of slope
  function test_GetUnlockedPercentage_BaseSlope() bs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 20e16); // no slope
    testCases[1] = TestCase(0, 2, 314285714285714285); // fractional slope
    testCases[2] = TestCase(0, 7, 60e16); // half slope
    testCases[3] = TestCase(0, 14, 100e16); // full slope
    testCases[4] = TestCase(0, 20, 100e16); // excede slope
    run(testCases);
  }

  // ======================================
  // with: Base Cliff Slope
  // without: Lock 
  // ======================================

  /// @notice With base reward at 20%, cliff reward at 30% and slope reward at 50%
  modifier bcs_setUp() {
    basePercentage = 20e16;
    lockPercentage = 0;
    cliffPercentage = 30e16;
    slopePercentage = 50e16;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 14;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseCliffSlope_Fuzz(uint32 cliff_, uint32 slope_) bcs_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice no cliff and varitations of slope
  function test_GetUnlockedPercentage_BaseCliffSlope_NoCliff() bcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 20e16); // no slope
    testCases[1] = TestCase(0, 2, 271428571428571428); // fractional slope
    testCases[2] = TestCase(0, 7, 45e16); // half slope
    testCases[3] = TestCase(0, 14, 70e16); // full slope
    testCases[4] = TestCase(0, 20, 70e16); // excede slope
    run(testCases);
  }

  /// @notice fractional cliff and variation on slope
  function test_GetUnlockedPercentage_BaseCliffSlope_FractionalCliff() bcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(2, 0, 242857142857142857); // no slope
    testCases[1] = TestCase(2, 2, 314285714285714285); // fractional slope
    testCases[2] = TestCase(2, 7, 492857142857142857); // half slope
    testCases[3] = TestCase(2, 14, 742857142857142857); // full slope
    testCases[4] = TestCase(2, 20, 742857142857142857); // excede slope
    run(testCases);
  }

  /// @notice half cliff and variations of slope
  function test_GetUnlockedPercentage_BaseCliffSlope_HalfCliff() bcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(7, 0, 35e16); // no slope
    testCases[1] = TestCase(7, 2, 421428571428571428); // fractional slope
    testCases[2] = TestCase(7, 7, 60e16); // half slope
    testCases[3] = TestCase(7, 14, 85e16); // full slope
    testCases[4] = TestCase(7, 20, 85e16); // excede slope
    run(testCases);
  }

  /// @notice full cliff and variations of slope
  function test_GetUnlockedPercentage_BaseCliffSlope_FullCliff() bcs_setUp public {
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
  function test_GetUnlockedPercentage_BaseCliffSlope_ExceedCliff() bcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(20, 0, 50e16); // no slope
    testCases[1] = TestCase(20, 2, 571428571428571428); // fractional slope
    testCases[2] = TestCase(20, 7, 75e16); // half slope
    testCases[3] = TestCase(20, 14, 100e16); // full slope
    testCases[4] = TestCase(20, 20, 100e16); // excede slope
    run(testCases);
  }

  // ======================================
  // with: Base Lock 
  // without: Cliff Slope
  // ======================================

  /// @notice With base reward at 50% and lock reward at 50%
  modifier bl_setUp() {
    basePercentage = 50e16;
    lockPercentage = 50e16;
    cliffPercentage = 0;
    slopePercentage = 0;
    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseLock_Fuzz(uint32 cliff_, uint32 slope_) bl_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice variatons of lock
  function test_GetUnlockedPercentage_BaseLock() bl_setUp public {
    TestCase[] memory testCases = new TestCase[](4);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 50e16); // no lock
    testCases[1] = TestCase(1, 0, 100e16); // cliff lock
    testCases[2] = TestCase(0, 1, 100e16); // slope lock
    testCases[3] = TestCase(1, 1, 100e16); // both
    run(testCases);
  }

  // ======================================
  // with: Base Lock Cliff
  // without: Slope
  // ======================================

  /// @notice With base reward at 10%, lock reward at 10%, and cliff reward at 80%
  modifier blc_setUp() {
    basePercentage = 10e16;
    lockPercentage = 10e16;
    cliffPercentage = 80e16;
    slopePercentage = 0;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 0;
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseLockCliff_Fuzz(uint32 cliff_, uint32 slope_) blc_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    uint256 pctWithCliff = airgrab.getUnlockedPercentage(0, cliff_);
    require(pctWithCliff <= 100e16, "unlocked should always be < 100%");
    if (cliff_ > 0) {
      // Slope doesn't influence
      assertEq(airgrab.getUnlockedPercentage(slope_, cliff_), pctWithCliff);
    } else if (slope_ > 0) {
      // Slopes opens unlock
      require(airgrab.getUnlockedPercentage(slope_, cliff_) > pctWithCliff, "unlocked should increase");
    }
  }

  /// @notice variations of cliff
  function test_GetUnlockedPercentage_BaseLockCliff() blc_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 10e16); // no cliff
    testCases[1] = TestCase(2, 0, 314285714285714285); // fractional cliff
    testCases[2] = TestCase(7, 0, 60e16); // half cliff
    testCases[3] = TestCase(14, 0, 100e16); // full cliff
    testCases[4] = TestCase(20, 0, 100e16); // excede cliff
    run(testCases);
  }

  // ======================================
  // with: Base Lock Slope
  // without: Cliff
  // ======================================

  /// @notice With base reward at 10%, lock reward at 10%, and slope reward at 80%
  modifier bls_setUp() {
    basePercentage = 10e16;
    lockPercentage = 10e16;
    cliffPercentage = 0;
    slopePercentage = 80e16;
    requiredSlopePeriod = 0;
    requiredSlopePeriod = 14; // weeks ~= 3 months
    initAirgrab();
    _;
  }

  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseLockSlope_Fuzz(uint32 cliff_, uint32 slope_) bls_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    uint256 pctWithSlope = airgrab.getUnlockedPercentage(slope_, 0);
    require(pctWithSlope <= 100e16, "unlocked should always be <= 100%");
    if (slope_ > 0) {
      // Cliff doesn't influence
      assertEq(airgrab.getUnlockedPercentage(slope_, cliff_), pctWithSlope);
    } else if (cliff_ > 0) {
      // Cliff opens unlock
      require(airgrab.getUnlockedPercentage(slope_, cliff_) > pctWithSlope, "unlocked should increase");
    }
  }

  /// @notice variations of slope
  function test_GetUnlockedPercentage_BaseLockSlope() bls_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 10e16); // no slope
    testCases[1] = TestCase(0, 2, 314285714285714285); // fractional slope
    testCases[2] = TestCase(0, 7, 60e16); // half slope
    testCases[3] = TestCase(0, 14, 100e16); // full slope
    testCases[4] = TestCase(0, 20, 100e16); // excede slope
    run(testCases);
  }

  // ======================================
  // with: Base Lock Cliff Slope
  // ======================================

  /// @notice With base reward at 10%, lock reward at 10%, 
  /// slope reward at 30%, and cliff reward at 50%
  modifier blcs_setUp() {
    basePercentage = 10e16;
    lockPercentage = 10e16;
    cliffPercentage = 30e16;
    slopePercentage = 50e16;
    requiredCliffPeriod = 14; // weeks ~= 3 months
    requiredSlopePeriod = 14;
    initAirgrab();
    _;
  }
  
  /// @notice fuzz on cliff and slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_Fuzz(uint32 cliff_, uint32 slope_) blcs_setUp public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);
    require(airgrab.getUnlockedPercentage(slope_, cliff_) <= 100e16);
  }

  /// @notice no cliff and varitations of slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_NoCliff() blcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(0, 0, 10e16); // no slope
    testCases[1] = TestCase(0, 2, 271428571428571428); // fractional slope
    testCases[2] = TestCase(0, 7, 45e16); // half slope
    testCases[3] = TestCase(0, 14, 70e16); // full slope
    testCases[4] = TestCase(0, 20, 70e16); // excede slope
    run(testCases);
  }

  /// @notice fractional cliff and variation on slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_FractionalCliff() blcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(2, 0, 242857142857142857); // no slope
    testCases[1] = TestCase(2, 2, 314285714285714285); // fractional slope
    testCases[2] = TestCase(2, 7, 492857142857142857); // half slope
    testCases[3] = TestCase(2, 14, 742857142857142857); // full slope
    testCases[4] = TestCase(2, 20, 742857142857142857); // excede slope
    run(testCases);
  }

  /// @notice half cliff and variations of slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_HalfCliff() blcs_setUp public {
    TestCase[] memory testCases = new TestCase[](5);
    // TestCase(cliff, slope, expectedPercentage)
    testCases[0] = TestCase(7, 0, 35e16); // no slope
    testCases[1] = TestCase(7, 2, 421428571428571428); // fractional slope
    testCases[2] = TestCase(7, 7, 60e16); // half slope
    testCases[3] = TestCase(7, 14, 85e16); // full slope
    testCases[4] = TestCase(7, 20, 85e16); // excede slope
    run(testCases);
  }

  /// @notice full cliff and variations of slope
  function test_GetUnlockedPercentage_BaseLockCliffSlope_FullCliff() blcs_setUp public {
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
  function test_GetUnlockedPercentage_BaseLockCliffSlope_ExceedCliff() blcs_setUp public {
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
