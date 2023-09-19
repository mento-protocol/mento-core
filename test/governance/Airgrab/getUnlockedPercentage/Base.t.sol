// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airgrab_Test } from "../Base.t.sol";
import { console } from "forge-std-next/console.sol";

contract GetUnlockedPercentage_Airgrab_Test is Airgrab_Test {
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
}
