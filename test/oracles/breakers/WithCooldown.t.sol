// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;

import { Test, console2 as console } from "celo-foundry/Test.sol";
import { WithCooldown } from "contracts/oracles/breakers/WithCooldown.sol";

contract WithCooldownTest is WithCooldown, Test {
  function test_setDefaultCooldownTime() public {
    uint256 testCooldown = 39 minutes;
    vm.expectEmit(true, true, true, true);
    emit DefaultCooldownTimeUpdated(testCooldown);
    _setDefaultCooldownTime(testCooldown);
    assertEq(defaultCooldownTime, testCooldown);
  }

  function test_setCooldownTimes_withZeroAddress_reverts() public {
    address[] memory rateFeedIDs = new address[](1);
    uint256[] memory cooldownTimes = new uint256[](1);

    vm.expectRevert("rate feed invalid");
    _setCooldownTimes(rateFeedIDs, cooldownTimes);
  }

  function test_setCooldownTimes_withMismatchingArrays_reverts() public {
    address[] memory rateFeedIDs = new address[](2);
    uint256[] memory cooldownTimes = new uint256[](1);

    vm.expectRevert("array length missmatch");
    _setCooldownTimes(rateFeedIDs, cooldownTimes);
  }

  function test_setCoolDownTimes_emitsEvents() public {
    address[] memory rateFeedIDs = new address[](2);
    uint256[] memory cooldownTimes = new uint256[](2);

    rateFeedIDs[0] = address(1111);
    rateFeedIDs[1] = address(2222);
    cooldownTimes[0] = 1;
    cooldownTimes[1] = 2;

    vm.expectEmit(true, true, true, true);
    emit RateFeedCooldownTimeUpdated(rateFeedIDs[0], cooldownTimes[0]);
    vm.expectEmit(true, true, true, true);
    emit RateFeedCooldownTimeUpdated(rateFeedIDs[1], cooldownTimes[1]);

    _setCooldownTimes(rateFeedIDs, cooldownTimes);

    assertEq(rateFeedCooldownTime[rateFeedIDs[0]], cooldownTimes[0]);
    assertEq(rateFeedCooldownTime[rateFeedIDs[1]], cooldownTimes[1]);
  }

  function test_getCooldown_whenNoRateFeedSpecific_usesDefault() public {
    uint256 testCooldown = 39 minutes;
    address rateFeedID = address(1111);
    _setDefaultCooldownTime(testCooldown);

    assertEq(getCooldown(rateFeedID), testCooldown);
  }

  function test_getCooldown_whenRateFeedSpecific_usesRateSpecific() public {
    uint256 testCooldown = 39 minutes;
    uint256 defaultCooldown = 10 minutes;
    address rateFeedID = address(1111);

    address[] memory rateFeedIDs = new address[](1);
    rateFeedIDs[0] = rateFeedID;
    uint256[] memory cooldownTimes = new uint256[](1);
    cooldownTimes[0] = testCooldown;

    _setCooldownTimes(rateFeedIDs, cooldownTimes);
    _setDefaultCooldownTime(defaultCooldown);

    assertEq(getCooldown(rateFeedID), testCooldown);
  }
}
