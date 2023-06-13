// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;

import { Test, console2 as console } from "celo-foundry/Test.sol";

import { MockBreaker } from "./mocks/MockBreaker.sol";
import { MockSortedOracles } from "./mocks/MockSortedOracles.sol";

import { WithRegistry } from "./utils/WithRegistry.t.sol";

import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { BreakerBox } from "contracts/BreakerBox.sol";

contract BreakerBoxTest is Test, WithRegistry {
  address deployer;
  address rateFeedID1;
  address rateFeedID2;
  address rateFeedID3;
  address notDeployer;

  MockBreaker mockBreaker1;
  MockBreaker mockBreaker2;
  MockBreaker mockBreaker3;
  MockBreaker mockBreaker4;
  BreakerBox breakerBox;
  MockSortedOracles sortedOracles;

  event BreakerAdded(address indexed breaker);
  event BreakerRemoved(address indexed breaker);
  event BreakerTripped(address indexed breaker, address indexed rateFeedID);
  event TradingModeUpdated(address indexed rateFeedID, uint256 tradingMode);
  event ResetSuccessful(address indexed rateFeedID, address indexed breaker);
  event ResetAttemptCriteriaFail(address indexed rateFeedID, address indexed breaker);
  event ResetAttemptNotCool(address indexed rateFeedID, address indexed breaker);
  event RateFeedAdded(address indexed rateFeedID);
  event RateFeedRemoved(address indexed rateFeedID);
  event SortedOraclesUpdated(address indexed newSortedOracles);
  event BreakerStatusUpdated(address breaker, address rateFeedID, bool status);

  function setUp() public {
    deployer = actor("deployer");
    rateFeedID1 = actor("rateFeedID1");
    rateFeedID2 = actor("rateFeedID2");
    rateFeedID3 = actor("rateFeedID3");
    notDeployer = actor("notDeployer");

    address[] memory testRateFeedIDs = new address[](2);
    testRateFeedIDs[0] = rateFeedID1;
    testRateFeedIDs[1] = rateFeedID2;

    vm.startPrank(deployer);
    mockBreaker1 = new MockBreaker(0, false, false);
    mockBreaker2 = new MockBreaker(0, false, false);
    mockBreaker3 = new MockBreaker(0, false, false);
    mockBreaker4 = new MockBreaker(0, false, false);
    sortedOracles = new MockSortedOracles();

    sortedOracles.addOracle(rateFeedID1, actor("oracleClient1"));
    sortedOracles.addOracle(rateFeedID2, actor("oracleClient1"));

    breakerBox = new BreakerBox(testRateFeedIDs, ISortedOracles(address(sortedOracles)));
    breakerBox.addBreaker(address(mockBreaker1), 1);
  }

  function isRateFeed(address rateFeedID) public view returns (bool rateFeedIDFound) {
    address[] memory allRateFeedIDs = breakerBox.getRateFeeds();
    for (uint256 i = 0; i < allRateFeedIDs.length; i++) {
      if (allRateFeedIDs[i] == rateFeedID) {
        rateFeedIDFound = true;
        break;
      }
    }
  }

  /**
   * @notice  Adds specified breaker to the breakerBox, mocks calls with specified values
   * @param breaker Fake breaker to add
   * @param tradingMode The trading mode for the breaker
   * @param cooldown The cooldown time of the breaker
   * @param reset Bool indicating the result of calling breaker.shouldReset()
   * @param trigger Bool indicating the result of calling breaker.shouldTrigger()
   * @param rateFeedID If rateFeedID is set, switch rateFeedID to the given trading mode
   */
  function setupBreakerAndRateFeed(
    MockBreaker breaker,
    uint8 tradingMode,
    uint256 cooldown,
    bool reset,
    bool trigger,
    address rateFeedID
  ) public {
    breaker.setCooldown(cooldown);
    breaker.setReset(reset);
    breaker.setTrigger(trigger);
    breakerBox.addBreaker(address(breaker), tradingMode);
    assertTrue(breakerBox.isBreaker(address(breaker)));

    if (rateFeedID != address(0)) {
      sortedOracles.addOracle(rateFeedID, actor("oracleClient"));
      breakerBox.addRateFeed(rateFeedID);
      breakerBox.toggleBreaker(address(breaker), rateFeedID, true);
      breakerBox.checkAndSetBreakers(rateFeedID);
      breakerBox.setRateFeedTradingMode(rateFeedID, tradingMode);
      assertTrue(isRateFeed(rateFeedID));
      assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID)), tradingMode);
      assertTrue(breakerBox.isBreakerEnabled(address(breaker), rateFeedID));
    }
  }

  function toggleAndAssertBreaker(
    address breaker,
    address rateFeedID,
    bool status
  ) public {
    vm.expectEmit(true, true, true, true);
    emit BreakerStatusUpdated(breaker, rateFeedID, status);
    breakerBox.toggleBreaker(breaker, rateFeedID, status);
    assertEq(breakerBox.isBreakerEnabled(breaker, rateFeedID), status);
  }
}

contract BreakerBoxTest_constructorAndSetters is BreakerBoxTest {
  /* ---------- Constructor ---------- */

  function test_constructor_shouldSetOwner() public {
    assertEq(breakerBox.owner(), deployer);
  }

  function test_constructor_shouldSetInitialBreaker() public {
    assertEq(uint256(breakerBox.breakerTradingMode(address(mockBreaker1))), 1);
    assertTrue(breakerBox.isBreaker(address(mockBreaker1)));
  }

  function test_constructor_shouldSetSortedOracles() public {
    assertEq(address(breakerBox.sortedOracles()), address(sortedOracles));
  }

  function test_constructor_shouldAddRateFeedIdsWithDefaultMode() public {
    assertTrue(breakerBox.rateFeedStatus(rateFeedID1));
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID1)), 0);

    assertTrue(breakerBox.rateFeedStatus(rateFeedID2));
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID2)), 0);
  }

  /* ---------- Breakers ---------- */

  function test_addBreaker_canOnlyBeCalledByOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(notDeployer);
    breakerBox.addBreaker(address(mockBreaker1), 2);
  }

  function test_addBreaker_whenAddingDuplicateBreaker_shouldRevert() public {
    vm.expectRevert("This breaker has already been added");
    breakerBox.addBreaker(address(mockBreaker1), 2);
  }

  function test_addBreaker_whenTradingModeIsDefault_shouldRevert() public {
    vm.expectRevert("The default trading mode can not have a breaker");
    breakerBox.addBreaker(address(mockBreaker4), 0);
  }

  function test_addBreaker_shouldUpdateAndEmit() public {
    vm.expectEmit(true, false, false, false);
    emit BreakerAdded(address(mockBreaker2));

    breakerBox.addBreaker(address(mockBreaker2), 2);

    assertEq(uint256(breakerBox.breakerTradingMode(address(mockBreaker2))), 2);
    assertTrue(breakerBox.isBreaker(address(mockBreaker2)));
  }

  function test_removeBreaker_canOnlyBeCalledByOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(notDeployer);
    breakerBox.removeBreaker(address(mockBreaker1));
  }

  function test_removeBreaker_whenBreakerHasntBeenAdded_shouldRevert() public {
    vm.expectRevert("Breaker has not been added");
    breakerBox.removeBreaker(address(mockBreaker2));
  }

  function test_removeBreaker_whenmultipleBreakers_shouldUpdateArray() public {
    breakerBox.addBreaker(address(mockBreaker2), 2);
    breakerBox.addBreaker(address(mockBreaker3), 3);
    breakerBox.addBreaker(address(mockBreaker4), 4);

    address[] memory allBreakers = breakerBox.getBreakers();
    assertEq(allBreakers.length, 4);
    assertEq(allBreakers[0], address(mockBreaker1));
    assertEq(allBreakers[1], address(mockBreaker2));
    assertEq(allBreakers[2], address(mockBreaker3));
    assertEq(allBreakers[3], address(mockBreaker4));

    breakerBox.removeBreaker(address(mockBreaker2));
    allBreakers = breakerBox.getBreakers();
    assertEq(allBreakers.length, 3);
    assertEq(allBreakers[0], address(mockBreaker1));
    assertEq(allBreakers[1], address(mockBreaker4));
    assertEq(allBreakers[2], address(mockBreaker3));
  }

  function test_removeBreaker_shouldUpdateStorageAndEmit() public {
    vm.warp(1672527600); // 2023-01-01 00:00:00
    setupBreakerAndRateFeed(mockBreaker2, 2, 10, false, true, rateFeedID3);
    assertTrue(breakerBox.isBreaker(address(mockBreaker2)));
    assertTrue(breakerBox.isBreakerEnabled(address(mockBreaker2), rateFeedID3));
    assertEq(uint256(breakerBox.breakerTradingMode(address(mockBreaker2))), 2);

    (uint256 tradingModeBefore, uint256 lastUpdatedTimeBefore, bool enabledBefore) = breakerBox.rateFeedBreakerStatus(
      rateFeedID3,
      address(mockBreaker2)
    );
    assertEq(tradingModeBefore, 2);
    assertEq(lastUpdatedTimeBefore, 1672527600);
    assertTrue(enabledBefore);

    vm.expectEmit(true, false, false, false);
    emit BreakerRemoved(address(mockBreaker2));
    breakerBox.removeBreaker(address(mockBreaker2));

    assertFalse(breakerBox.isBreaker(address(mockBreaker2)));
    assertFalse(breakerBox.isBreakerEnabled(address(mockBreaker2), rateFeedID3));
    assertEq(uint256(breakerBox.breakerTradingMode(address(mockBreaker2))), 0);

    (uint256 tradingModeAfter, uint256 lastUpdatedTimeAfter, bool enabledAfter) = breakerBox.rateFeedBreakerStatus(
      rateFeedID3,
      address(mockBreaker2)
    );
    assertEq(tradingModeAfter, 0);
    assertEq(lastUpdatedTimeAfter, 0);
    assertFalse(enabledAfter);
  }

  function test_toggleBreaker_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breakerBox.toggleBreaker(address(mockBreaker1), rateFeedID1, true);
  }

  function test_toggleBreaker_whenRateFeedIsNotRegistered_shouldRevert() public {
    vm.expectRevert("This rate feed has not been added to the BreakerBox");
    breakerBox.toggleBreaker(address(mockBreaker1), rateFeedID3, false);
  }

  function test_toggleBreaker_whenBreakerIsNotRegistered_shouldRevert() public {
    vm.expectRevert("This breaker has not been added to the BreakerBox");
    breakerBox.toggleBreaker(address(mockBreaker3), rateFeedID1, true);
  }

  function test_toggleBreaker_whenSenderIsOwner_shouldToggleAndEmit() public {
    toggleAndAssertBreaker(address(mockBreaker1), rateFeedID1, true);
    toggleAndAssertBreaker(address(mockBreaker1), rateFeedID1, false);
  }

  function test_toggleBreaker_whenBreakerIsRemoved_shouldUpdateTradingModeAndBreakerStatus() public {
    setupBreakerAndRateFeed(mockBreaker3, 1, 10, false, true, rateFeedID3);
    setupBreakerAndRateFeed(mockBreaker4, 2, 10, false, true, address(0));
    breakerBox.toggleBreaker(address(mockBreaker4), rateFeedID3, true);
    breakerBox.checkAndSetBreakers(rateFeedID3);

    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 2 | 1);

    breakerBox.toggleBreaker(address(mockBreaker4), rateFeedID3, false);
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 1);
    assertFalse(breakerBox.isBreakerEnabled(address(mockBreaker4), rateFeedID3));
  }

  /* ---------- Rate Feed IDs ---------- */

  function test_addRateFeed_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breakerBox.addRateFeed(rateFeedID3);
  }

  function test_addRateFeed_whenAlreadyAdded_shouldRevert() public {
    vm.expectRevert("Rate feed ID has already been added");
    breakerBox.addRateFeed(rateFeedID1);
  }

  function test_addRateFeed_whenRateFeedDoesNotExistInOracleList_shouldRevert() public {
    vm.expectRevert("Rate feed ID does not exist as it has 0 oracles");
    breakerBox.addRateFeed(rateFeedID3);
  }

  function test_addRateFeed_whenRateFeedExistsInOracleList_shouldSetDefaultModeAndEmit() public {
    sortedOracles.addOracle(rateFeedID3, actor("oracleAddress"));

    uint256 tradingModeBefore = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(tradingModeBefore, 0);
    assertFalse(isRateFeed(rateFeedID3));
    assertFalse(breakerBox.rateFeedStatus(rateFeedID3));

    vm.expectEmit(true, true, true, true);
    emit RateFeedAdded(rateFeedID3);
    breakerBox.addRateFeed(rateFeedID3);

    uint256 tradingModeAfter = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(tradingModeAfter, 0);
    assertTrue(isRateFeed(rateFeedID3));
    assertTrue(breakerBox.rateFeedStatus(rateFeedID3));
  }

  function test_removeRateFeed_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breakerBox.removeRateFeed(rateFeedID1);
  }

  function test_removeRateFeed_whenRateFeedHasNotBeenAdded_shouldRevert() public {
    vm.expectRevert("Rate feed ID has not been added");
    breakerBox.removeRateFeed(rateFeedID3);
  }

  function test_removeRateFeed_shouldRemoveRateFeedFromArray() public {
    assertTrue(isRateFeed(rateFeedID1));
    breakerBox.removeRateFeed(rateFeedID1);
    assertFalse(isRateFeed(rateFeedID1));
  }

  function test_removeRateFeed_shouldResetTradingModeInfoAndEmit() public {
    toggleAndAssertBreaker(address(mockBreaker1), rateFeedID1, true);
    breakerBox.setRateFeedTradingMode(rateFeedID1, 1);

    uint256 tradingModeBefore = breakerBox.getRateFeedTradingMode(rateFeedID1);
    assertEq(tradingModeBefore, 1);
    assertTrue(isRateFeed(rateFeedID1));
    assertTrue(breakerBox.rateFeedStatus(rateFeedID1));
    (, , bool breakerStatusBefore) = breakerBox.rateFeedBreakerStatus(rateFeedID1, address(mockBreaker1));
    assertTrue(breakerStatusBefore);

    vm.expectEmit(true, true, true, true);
    emit RateFeedRemoved(rateFeedID1);
    breakerBox.removeRateFeed(rateFeedID1);

    uint256 tradingModeAfter = breakerBox.getRateFeedTradingMode(rateFeedID1);
    assertEq(tradingModeAfter, 0);
    assertFalse(isRateFeed(rateFeedID1));
    assertFalse(breakerBox.rateFeedStatus(rateFeedID1));
    (, , bool breakerStatusAfter) = breakerBox.rateFeedBreakerStatus(rateFeedID1, address(mockBreaker1));
    assertFalse(breakerStatusAfter);
  }

  function test_setRateFeedTradingMode_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breakerBox.setRateFeedTradingMode(rateFeedID1, 9);
  }

  function test_setRateFeedTradingMode_whenRateFeedHasNotBeenAdded_ShouldRevert() public {
    vm.expectRevert("Rate feed ID has not been added");
    breakerBox.setRateFeedTradingMode(rateFeedID3, 1);
  }

  function test_setRateFeedTradingMode_ShouldUpdateAndEmit() public {
    uint256 tradingModeBefore = breakerBox.getRateFeedTradingMode(rateFeedID1);
    assertEq(tradingModeBefore, 0);

    vm.expectEmit(true, true, true, true);
    emit TradingModeUpdated(rateFeedID1, 1);
    breakerBox.setRateFeedTradingMode(rateFeedID1, 1);

    uint256 tradingModeAfter = breakerBox.getRateFeedTradingMode(rateFeedID1);
    assertEq(tradingModeAfter, 1);
  }

  /* ---------- Sorted Oracles ---------- */

  function test_setSortedOracles_whenSenderIsNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breakerBox.setSortedOracles(ISortedOracles(address(0)));
  }

  function test_setSortedOracles_whenAddressIsZero_shouldRevert() public {
    vm.expectRevert("SortedOracles address must be set");
    breakerBox.setSortedOracles(ISortedOracles(address(0)));
  }

  function test_setSortedOracles_whenSenderIsOwner_shouldUpdateAndEmit() public {
    address newSortedOracles = actor("newSortedOracles");
    vm.expectEmit(true, true, true, true);
    emit SortedOraclesUpdated(newSortedOracles);

    breakerBox.setSortedOracles(ISortedOracles(newSortedOracles));

    assertEq(address(breakerBox.sortedOracles()), newSortedOracles);
  }
}

contract BreakerBoxTest_checkAndSetBreakers is BreakerBoxTest {
  function test_checkAndSetBreakers_whenRateFeedIsNotInDefaultModeAndCooldownNotPassed_shouldEmitNotCool() public {
    setupBreakerAndRateFeed(mockBreaker3, 3, 3600, false, true, rateFeedID3);

    skip(3599);

    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectEmit(true, true, true, true);
    emit ResetAttemptNotCool(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 3);
  }

  function test_checkAndSetBreakers_whenRateFeedIsNotInDefaultModeAndCantReset_shouldEmitCriteriaFail() public {
    setupBreakerAndRateFeed(mockBreaker3, 3, 3600, false, true, rateFeedID3);

    skip(3600);
    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.shouldReset.selector, rateFeedID3));
    vm.expectEmit(true, true, true, true);
    emit ResetAttemptCriteriaFail(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 3);
  }

  function test_checkAndSetBreakers_whenRateFeedIsNotInDefaultModeAndCanReset_shouldResetMode() public {
    setupBreakerAndRateFeed(mockBreaker3, 3, 3600, true, true, rateFeedID3);

    skip(3600);

    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.shouldReset.selector, rateFeedID3));
    vm.expectEmit(true, true, true, true);
    emit ResetSuccessful(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 0);
  }

  function test_checkAndSetBreakers_whenRateFeedIsNotInDefaultModeAndNoBreakerCooldown_shouldReturnCorrectModeAndEmit()
    public
  {
    setupBreakerAndRateFeed(mockBreaker3, 3, 0, false, true, rateFeedID3);

    skip(3600);

    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectEmit(true, true, true, true);
    emit ResetAttemptNotCool(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 3);
  }

  function test_checkAndSetBreakers_whenNoBreakersAreTripped_shouldReturnDefaultMode() public {
    setupBreakerAndRateFeed(mockBreaker3, 6, 3600, false, false, address(0));

    sortedOracles.addOracle(rateFeedID3, actor("oracleClient3"));
    breakerBox.addRateFeed(rateFeedID3);
    assertTrue(isRateFeed(rateFeedID3));

    toggleAndAssertBreaker(address(mockBreaker3), rateFeedID3, true);
    toggleAndAssertBreaker(address(mockBreaker1), rateFeedID3, true);

    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 0);

    vm.expectCall(
      address(mockBreaker3),
      abi.encodeWithSelector(mockBreaker3.shouldTrigger.selector, address(rateFeedID3))
    );
    vm.expectCall(
      address(mockBreaker1),
      abi.encodeWithSelector(mockBreaker1.shouldTrigger.selector, address(rateFeedID3))
    );
    breakerBox.checkAndSetBreakers(rateFeedID3);

    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 0);
  }

  function test_checkAndSetBreakers_whenABreakerIsTripped_shouldSetModeAndEmit() public {
    MockBreaker mockBreaker5 = new MockBreaker(60, true, false);

    sortedOracles.addOracle(rateFeedID3, actor("oracleReport3"));
    breakerBox.addRateFeed(rateFeedID3);
    assertTrue(isRateFeed(rateFeedID3));

    breakerBox.addBreaker(address(mockBreaker5), 3);
    assertTrue(breakerBox.isBreaker(address(mockBreaker5)));
    toggleAndAssertBreaker(address(mockBreaker5), rateFeedID3, true);

    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 0);
    (uint256 breakerTradingModeBefore, , ) = breakerBox.rateFeedBreakerStatus(rateFeedID3, address(mockBreaker5));
    assertEq(breakerTradingModeBefore, 0);

    vm.expectCall(
      address(mockBreaker5),
      abi.encodeWithSelector(mockBreaker5.shouldTrigger.selector, address(rateFeedID3))
    );

    vm.expectEmit(true, true, true, true);
    emit BreakerTripped(address(mockBreaker5), rateFeedID3);
    breakerBox.checkAndSetBreakers(rateFeedID3);

    (uint256 breakerTradingModeAfter, uint256 breakerLastUpdatedTime, bool breakerEnabled) = breakerBox
      .rateFeedBreakerStatus(rateFeedID3, address(mockBreaker5));
    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 3);
    assertEq(breakerTradingModeAfter, 3);
    assertEq(breakerLastUpdatedTime, 1);
    assertTrue(breakerEnabled);
  }

  function test_checkAndSetBreakers_whenABreakerIsNotEnabled_shouldNotTrigger() public {
    MockBreaker mockBreaker5 = new MockBreaker(60, true, true);

    sortedOracles.addOracle(rateFeedID3, actor("oracleReport3"));
    breakerBox.addRateFeed(rateFeedID3);
    assertTrue(isRateFeed(rateFeedID3));

    breakerBox.addBreaker(address(mockBreaker5), 3);
    assertTrue(breakerBox.isBreaker(address(mockBreaker5)));

    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 0);
    (, , bool breakerEnabled) = breakerBox.rateFeedBreakerStatus(rateFeedID3, address(mockBreaker5));
    assertFalse(breakerEnabled);

    breakerBox.checkAndSetBreakers(rateFeedID3);

    assertEq(uint256(breakerBox.getRateFeedTradingMode(rateFeedID3)), 0);
  }

  function test_checkAndSetBreakers_whenCooldownOneSecond_shouldSetStatusCorrectly() public {
    vm.warp(1672527600); // 2023-01-01 00:00:00

    setupBreakerAndRateFeed(mockBreaker3, 2, 1 seconds, false, true, rateFeedID3);

    (uint256 breakerTradingMode1, uint256 breakerLastUpdatedTime1, bool breakerEnabled1) = breakerBox
      .rateFeedBreakerStatus(rateFeedID3, address(mockBreaker3));
    uint256 tradingMode1 = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(breakerTradingMode1, 2);
    assertEq(breakerLastUpdatedTime1, 1672527600);
    assertTrue(breakerEnabled1);
    assertEq(tradingMode1, 2);

    vm.warp(1672527605); // 2023-01-01 00:00:05
    mockBreaker3.setTrigger(false);
    mockBreaker3.setReset(true);
    breakerBox.checkAndSetBreakers(rateFeedID3);

    (uint256 breakerTradingMode2, uint256 breakerLastUpdatedTime2, bool breakerEnabled2) = breakerBox
      .rateFeedBreakerStatus(rateFeedID3, address(mockBreaker3));
    uint256 tradingMode2 = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(breakerTradingMode2, 0);
    assertEq(breakerLastUpdatedTime2, 1672527605);
    assertTrue(breakerEnabled2);
    assertEq(tradingMode2, 0);

    vm.warp(1672527610); // 2023-01-01 00:00:10
    mockBreaker3.setTrigger(true);
    mockBreaker3.setReset(false);
    breakerBox.checkAndSetBreakers(rateFeedID3);

    (uint256 breakerTradingMode3, uint256 breakerLastUpdatedTime3, bool breakerEnabled3) = breakerBox
      .rateFeedBreakerStatus(rateFeedID3, address(mockBreaker3));
    uint256 tradingMode3 = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(breakerTradingMode3, 2);
    assertEq(breakerLastUpdatedTime3, 1672527610);
    assertTrue(breakerEnabled3);
    assertEq(tradingMode3, 2);
  }

  function test_checkAndSetBreakers_whenCooldownTenSeconds_shouldSetStatusCorrectly() public {
    vm.warp(1672527600); // 2023-01-01 00:00:00

    setupBreakerAndRateFeed(mockBreaker3, 2, 1 seconds, false, true, rateFeedID3);

    (uint256 breakerTradingMode1, uint256 breakerLastUpdatedTime1, bool breakerEnabled1) = breakerBox
      .rateFeedBreakerStatus(rateFeedID3, address(mockBreaker3));
    uint256 tradingMode1 = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(breakerTradingMode1, 2);
    assertEq(breakerLastUpdatedTime1, 1672527600);
    assertTrue(breakerEnabled1);
    assertEq(tradingMode1, 2);

    vm.warp(1672527605); // 2023-01-01 00:00:05
    mockBreaker3.setTrigger(false);
    mockBreaker3.setReset(true);
    breakerBox.checkAndSetBreakers(rateFeedID3);

    (uint256 breakerTradingMode2, uint256 breakerLastUpdatedTime2, bool breakerEnabled2) = breakerBox
      .rateFeedBreakerStatus(rateFeedID3, address(mockBreaker3));
    uint256 tradingMode2 = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(breakerTradingMode2, 0);
    assertEq(breakerLastUpdatedTime2, 1672527605);
    assertTrue(breakerEnabled2);
    assertEq(tradingMode2, 0);

    vm.warp(1672527610); // 2023-01-01 00:00:10
    mockBreaker3.setTrigger(true);
    mockBreaker3.setReset(false);
    breakerBox.checkAndSetBreakers(rateFeedID3);

    (uint256 breakerTradingMode3, uint256 breakerLastUpdatedTime3, bool breakerEnabled3) = breakerBox
      .rateFeedBreakerStatus(rateFeedID3, address(mockBreaker3));
    uint256 tradingMode3 = breakerBox.getRateFeedTradingMode(rateFeedID3);
    assertEq(breakerTradingMode3, 2);
    assertEq(breakerLastUpdatedTime3, 1672527610);
    assertTrue(breakerEnabled3);
    assertEq(tradingMode3, 2);
  }

  function test_checkAndSetBreakers_whenMultipleBreakersAreEnabled_shouldCalculateTradingModeCorrectly() public {
    MockBreaker mockBreaker5 = new MockBreaker(60, true, false);
    MockBreaker mockBreaker6 = new MockBreaker(60, true, false);
    breakerBox.addBreaker(address(mockBreaker5), 1);
    breakerBox.addBreaker(address(mockBreaker6), 2);
    breakerBox.toggleBreaker(address(mockBreaker5), rateFeedID2, true);
    breakerBox.toggleBreaker(address(mockBreaker6), rateFeedID2, true);

    uint256 tradingModeBefore = breakerBox.getRateFeedTradingMode(rateFeedID2);
    assertEq(tradingModeBefore, 0);

    breakerBox.checkAndSetBreakers(rateFeedID2);
    uint256 tradingModeAfter = breakerBox.getRateFeedTradingMode(rateFeedID2);
    assertEq(tradingModeAfter, 1 | 2);

    mockBreaker5.setTrigger(false);
    mockBreaker5.setReset(true);
    skip(60);

    breakerBox.checkAndSetBreakers(rateFeedID2);
    uint256 tradingModeAfter2 = breakerBox.getRateFeedTradingMode(rateFeedID2);
    assertEq(tradingModeAfter2, 2);
  }
}
