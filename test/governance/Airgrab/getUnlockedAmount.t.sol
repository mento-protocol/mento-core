// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Airgrab_Test } from "./Base.t.sol";
import { console } from "forge-std-next/console.sol";

contract GetUnlockedAmount_Airgrab_Test is Airgrab_Test {
  /// @notice Test subject parameters
  uint256 amount;
  uint32 slope;
  uint32 cliff;

  /// @notice Test subject `getUnlockedAmount`
  function subject() internal view returns (uint256) {
    return airgrab.getUnlockedAmount(amount, slope, cliff);
  }

  /// @notice When there's no required cliff and slope, returns the full amount
  function test_GetUnlockedAmount_whenNoLockRequired_Fuzz(
    uint256 amount_,
    uint32 cliff_,
    uint32 slope_
  ) public {
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);

    requiredCliffPeriod = 0;
    requiredSlopePeriod = 0;
    initAirgrab();

    amount = amount_;
    slope = slope_;
    cliff = cliff_;
    assertEq(subject(), amount_);
  }

  /// @notice When there's a required cliff and slope, uses the percentage to scale the amount
  function test_GetUnlockedAmount_whenLockRequired_Fuzz(
    uint256 amount_,
    uint32 cliff_,
    uint32 slope_
  ) public {
    vm.assume(amount_ <= type(uint96).max);
    vm.assume(cliff_ <= MAX_CLIFF_PERIOD);
    vm.assume(slope_ <= MAX_SLOPE_PERIOD);

    requiredCliffPeriod = 14;
    requiredSlopePeriod = 14;
    initAirgrab();

    uint256 unlockedPercentage = airgrab.getUnlockedPercentage(slope_, cliff_);

    amount = amount_;
    slope = slope_;
    cliff = cliff_;
    assertEq(subject(), (amount_ * unlockedPercentage) / 1e18);
  }
}
