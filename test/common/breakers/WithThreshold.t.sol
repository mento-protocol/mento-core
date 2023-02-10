// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { WithThreshold } from "contracts/common/breakers/WithThreshold.sol";

contract WithThresholdTest is WithThreshold, Test {
  function test_setDefaultRateChangeThreshold() public {
    uint256 testThreshold = 1e20;
    vm.expectEmit(true, true, true, true);
    emit DefaultRateChangeThresholdUpdated(testThreshold);
    _setDefaultRateChangeThreshold(testThreshold);
    assertEq(defaultRateChangeThreshold.unwrap(), testThreshold);
  }

  function test_setRateChangeThresholds_withZeroAddress_reverts() public {
    address[] memory rateFeedIDs = new address[](1);
    uint256[] memory thresholds = new uint256[](1);

    vm.expectRevert("rate feed invalid");
    _setRateChangeThresholds(rateFeedIDs, thresholds);
  }

  function test_setRateChangeThresholds_withMismatchingArrays_reverts() public {
    address[] memory rateFeedIDs = new address[](2);
    uint256[] memory thresholds = new uint256[](1);

    vm.expectRevert("array length missmatch");
    _setRateChangeThresholds(rateFeedIDs, thresholds);
  }

  function test_setRateChangeThresholds_emitsEvents() public {
    address[] memory rateFeedIDs = new address[](2);
    uint256[] memory thresholds = new uint256[](2);

    rateFeedIDs[0] = address(1111);
    rateFeedIDs[1] = address(2222);
    thresholds[0] = 1e20;
    thresholds[1] = 2e20;

    vm.expectEmit(true, true, true, true);
    emit RateChangeThresholdUpdated(rateFeedIDs[0], thresholds[0]);
    vm.expectEmit(true, true, true, true);
    emit RateChangeThresholdUpdated(rateFeedIDs[1], thresholds[1]);

    _setRateChangeThresholds(rateFeedIDs, thresholds);

    assertEq(rateChangeThreshold[rateFeedIDs[0]].unwrap(), thresholds[0]);
    assertEq(rateChangeThreshold[rateFeedIDs[1]].unwrap(), thresholds[1]);
  }
}

contract WithThresholdTest_exceedsThreshold is WithThresholdTest {
  uint256 constant _1PC = 0.01 * 1e24; // 1%
  uint256 constant _10PC = 0.1 * 1e24; // 10%
  uint256 constant _20PC = 0.2 * 1e24; // 20%

  address rateFeedID0 = actor("rateFeedID0-10%");
  address rateFeedID1 = actor("rateFeedID2-1%");
  address rateFeedID2 = actor("rateFeedID3-default-20%");

  function setUp() public {
    uint256[] memory ts = new uint256[](2);
    ts[0] = _10PC;
    ts[1] = _1PC;
    address[] memory rateFeedIDs = new address[](2);
    rateFeedIDs[0] = rateFeedID0;
    rateFeedIDs[1] = rateFeedID1;

    _setDefaultRateChangeThreshold(_20PC);
    _setRateChangeThresholds(rateFeedIDs, ts);
  }

  function test_exceedsThreshold_withDefault_whenWithin_isFalse() public {
    assertEq(exceedsThreshold(1e24, 1.1 * 1e24, rateFeedID2), false);
    assertEq(exceedsThreshold(1e24, 0.9 * 1e24, rateFeedID2), false);
  }

  function test_exceedsThreshold_withDefault_whenNotWithin_isTrue() public {
    assertEq(exceedsThreshold(1e24, 1.3 * 1e24, rateFeedID2), true);
    assertEq(exceedsThreshold(1e24, 0.7 * 1e24, rateFeedID2), true);
  }

  function test_exceedsThreshold_withOverride_whenWithin_isTrue() public {
    assertEq(exceedsThreshold(1e24, 1.1 * 1e24, rateFeedID1), true);
    assertEq(exceedsThreshold(1e24, 0.9 * 1e24, rateFeedID1), true);
    assertEq(exceedsThreshold(1e24, 1.11 * 1e24, rateFeedID0), true);
    assertEq(exceedsThreshold(1e24, 0.89 * 1e24, rateFeedID0), true);
  }

  function test_exceedsThreshold_withOverride_whenNotWithin_isFalse() public {
    assertEq(exceedsThreshold(1e24, 1.01 * 1e24, rateFeedID1), false);
    assertEq(exceedsThreshold(1e24, 1.01 * 1e24, rateFeedID0), false);
  }
}