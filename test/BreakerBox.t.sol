// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.5.13;

import { Test, console2 as console } from "celo-foundry/Test.sol";

import { MockBreaker } from "./mocks/MockBreaker.sol";
import { MockSortedOracles } from "./mocks/MockSortedOracles.sol";

import { WithRegistry } from "./utils/WithRegistry.sol";

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

    changePrank(deployer);
    mockBreaker1 = new MockBreaker(0, false, false);
    mockBreaker2 = new MockBreaker(0, false, false);
    mockBreaker3 = new MockBreaker(0, false, false);
    mockBreaker4 = new MockBreaker(0, false, false);
    sortedOracles = new MockSortedOracles();
    breakerBox = new BreakerBox(true);

    sortedOracles.addOracle(rateFeedID1, actor("oracleClient1"));
    sortedOracles.addOracle(rateFeedID2, actor("oracleClient1"));

    breakerBox.initialize(testRateFeedIDs, ISortedOracles(address(sortedOracles)));
    breakerBox.addBreaker(address(mockBreaker1), 1);
  }

  function isRateFeed(address rateFeedID) public view returns (bool rateFeedIDFound) {
    address[] memory allRateFeedIDs = breakerBox.getrateFeeds();
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
    uint64 tradingMode,
    uint256 cooldown,
    bool reset,
    bool trigger,
    address rateFeedID
  ) public {
    vm.mockCall(address(breaker), abi.encodeWithSelector(breaker.getCooldown.selector), abi.encode(cooldown));

    vm.mockCall(address(breaker), abi.encodeWithSelector(breaker.shouldReset.selector), abi.encode(reset));

    vm.mockCall(address(breaker), abi.encodeWithSelector(breaker.shouldTrigger.selector), abi.encode(trigger));

    breakerBox.addBreaker(address(breaker), tradingMode);
    assertTrue(breakerBox.isBreaker(address(breaker)));

    if (rateFeedID != address(0)) {
      sortedOracles.addOracle(rateFeedID, actor("oracleClient"));
      breakerBox.addRateFeed(rateFeedID);
      assertTrue(isRateFeed(rateFeedID));

      breakerBox.setRateFeedTradingMode(rateFeedID, tradingMode);
      (uint256 savedTradingMode, , ) = breakerBox.rateFeedTradingModes(rateFeedID);
      assertEq(savedTradingMode, tradingMode);
    }
  }
}

contract BreakerBoxTest_constructorAndSetters is BreakerBoxTest {
  /* ---------- Initilizer ---------- */

  function test_initilize_shouldSetOwner() public view {
    assert(breakerBox.owner() == deployer);
  }

  function test_initilize_shouldSetInitialBreaker() public view {
    assert(breakerBox.tradingModeBreaker(1) == address(mockBreaker1));
    assert(breakerBox.breakerTradingMode(address(mockBreaker1)) == 1);
    assert(breakerBox.isBreaker(address(mockBreaker1)));
  }

  function test_initilize_shouldSetSortedOracles() public {
    assert(address(breakerBox.sortedOracles()) == address(sortedOracles));
  }

  function test_initilize_shouldAddRateFeedIdsWithDefaultMode() public view {
    (uint256 tradingModeA, uint256 lastUpdatedA, uint256 lastUpdatedBlockA) = breakerBox.rateFeedTradingModes(
      rateFeedID1
    );
    assert(tradingModeA == 0);
    assert(lastUpdatedA > 0);
    assert(lastUpdatedBlockA > 0);

    (uint256 tradingModeB, uint256 lastUpdatedB, uint256 lastUpdatedBlockB) = breakerBox.rateFeedTradingModes(
      rateFeedID2
    );
    assert(tradingModeB == 0);
    assert(lastUpdatedB > 0);
    assert(lastUpdatedBlockB > 0);
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

  function test_addBreaker_whenAddingBreakerWithDuplicateTradingMode_shouldRevert() public {
    vm.expectRevert("There is already a breaker added with the same trading mode");
    breakerBox.addBreaker(address(mockBreaker2), 1);
  }

  function test_addBreaker_whenAddingBreakerWithDefaultTradingMode_shouldRevert() public {
    vm.expectRevert("The default trading mode can not have a breaker");
    breakerBox.addBreaker(address(mockBreaker2), 0);
  }

  function test_addBreaker_shouldUpdateAndEmit() public {
    vm.expectEmit(true, false, false, false);
    emit BreakerAdded(address(mockBreaker2));

    breakerBox.addBreaker(address(mockBreaker2), 2);

    assert(breakerBox.tradingModeBreaker(2) == address(mockBreaker2));
    assert(breakerBox.breakerTradingMode(address(mockBreaker2)) == 2);
    assert(breakerBox.isBreaker(address(mockBreaker2)));
  }

  function test_removeBreaker_whenBreakerHasntBeenAdded_shouldRevert() public {
    vm.expectRevert("This breaker has not been added");
    breakerBox.removeBreaker(address(mockBreaker2));
  }

  function test_removeBreaker_whenBreakerTradingModeInUse_shouldSetDefaultMode() public {
    breakerBox.addBreaker(address(mockBreaker3), 3);
    sortedOracles.addOracle(rateFeedID3, actor("oracleClient3"));
    breakerBox.addRateFeed(rateFeedID3);
    breakerBox.setRateFeedTradingMode(rateFeedID3, 3);

    (uint256 tradingModeBefore, , ) = breakerBox.rateFeedTradingModes(rateFeedID3);
    assertEq(tradingModeBefore, 3);

    breakerBox.removeBreaker(address(mockBreaker3));

    (uint256 tradingModeAfter, , ) = breakerBox.rateFeedTradingModes(rateFeedID3);
    assertEq(tradingModeAfter, 0);
  }

  function test_removeBreaker_shouldUpdateStorageAndEmit() public {
    breakerBox.setBreakerEnabled(address(mockBreaker1), rateFeedID1, true);
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker1), rateFeedID1), true);

    vm.expectEmit(true, false, false, false);
    emit BreakerRemoved(address(mockBreaker1));

    assert(breakerBox.tradingModeBreaker(1) == address(mockBreaker1));
    assert(breakerBox.breakerTradingMode(address(mockBreaker1)) == 1);
    assert(breakerBox.isBreaker(address(mockBreaker1)));
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker1), rateFeedID3), false);

    breakerBox.removeBreaker(address(mockBreaker1));

    assert(breakerBox.tradingModeBreaker(1) == address(0));
    assert(breakerBox.breakerTradingMode(address(mockBreaker1)) == 0);
    assert(!breakerBox.isBreaker(address(mockBreaker1)));
  }

  function test_insertBreaker_whenBreakerHasAlreadyBeenAdded_shouldRevert() public {
    vm.expectRevert("This breaker has already been added");
    breakerBox.insertBreaker(address(mockBreaker1), 1, address(0), address(0));
  }

  function test_insertBreaker_whenAddingBreakerWithDuplicateTradingMode_shouldRevert() public {
    vm.expectRevert("There is already a breaker added with the same trading mode");
    breakerBox.insertBreaker(address(mockBreaker2), 1, address(0), address(0));
  }

  function test_insertBreaker_shouldInsertBreakerAtCorrectPositionAndEmit() public {
    assert(breakerBox.getBreakers().length == 1);

    breakerBox.addBreaker(address(mockBreaker2), 2);
    breakerBox.addBreaker(address(mockBreaker3), 3);

    address[] memory breakersBefore = breakerBox.getBreakers();
    assert(breakersBefore.length == 3);
    assert(breakersBefore[0] == address(mockBreaker1));
    assert(breakersBefore[1] == address(mockBreaker2));
    assert(breakersBefore[2] == address(mockBreaker3));

    vm.expectEmit(true, false, false, false);
    emit BreakerAdded(address(mockBreaker4));

    breakerBox.insertBreaker(address(mockBreaker4), 4, address(mockBreaker2), address(mockBreaker1));

    address[] memory breakersAfter = breakerBox.getBreakers();
    assert(breakersAfter.length == 4);
    assert(breakersAfter[0] == address(mockBreaker1));
    assert(breakersAfter[1] == address(mockBreaker4));
    assert(breakersAfter[2] == address(mockBreaker2));
    assert(breakersAfter[3] == address(mockBreaker3));

    assert(breakerBox.tradingModeBreaker(4) == address(mockBreaker4));
    assert(breakerBox.tradingModeBreaker(3) == address(mockBreaker3));
    assert(breakerBox.tradingModeBreaker(2) == address(mockBreaker2));
    assert(breakerBox.tradingModeBreaker(1) == address(mockBreaker1));

    assert(breakerBox.breakerTradingMode(address(mockBreaker4)) == 4);
  }

  function test_setBreakerEnabled_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breakerBox.setBreakerEnabled(address(mockBreaker1), rateFeedID1, true);
  }

  function test_setBreakerEnabled_whenRateFeedIsNotRegistered_shouldRevert() public {
    vm.expectRevert("this rate feed has not been registered");
    breakerBox.setBreakerEnabled(address(mockBreaker1), rateFeedID3, true);
  }

  function test_setBreakerEnabled_whenBreakerIsNotRegistered_shouldRevert() public {
    vm.expectRevert("this breaker has not been registered in the breakers list");
    breakerBox.setBreakerEnabled(address(mockBreaker3), rateFeedID1, true);
  }

  function test_setBreakerEnabled_whenSenderIsOwner_shouldEnableAndEmit() public {
    vm.expectEmit(true, true, true, true);
    emit BreakerStatusUpdated(address(mockBreaker1), rateFeedID1, true);
    breakerBox.setBreakerEnabled(address(mockBreaker1), rateFeedID1, true);

    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker1), rateFeedID1), true);
  }

  function test_disableBreaker_whenNotOwner_shouldRevert() public {
    changePrank(notDeployer);
    vm.expectRevert("Ownable: caller is not the owner");
    breakerBox.disableBreaker(address(mockBreaker1), rateFeedID1, false);
  }

  function test_disableBreaker_whenRateFeedIsNotRegistered_shouldRevert() public {
    vm.expectRevert("this rate feed has not been registered");
    breakerBox.disableBreaker(address(mockBreaker1), rateFeedID3, false);
  }

  function test_disableBreaker_whenBreakerIsNotRegistered_shouldRevert() public {
    vm.expectRevert("this breaker has not been registered in the breakers list");
    breakerBox.disableBreaker(address(mockBreaker3), rateFeedID1, false);
  }

  function test_disabkeBreaker_whenSenderIsOwner_shouldDisableAndEmit() public {
    vm.expectEmit(true, true, true, true);
    emit BreakerStatusUpdated(address(mockBreaker1), rateFeedID1, false);
    breakerBox.disableBreaker(address(mockBreaker1), rateFeedID1, false);

    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker1), rateFeedID1), false);
  }

  /* ---------- Rate Feed IDs ---------- */

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
    vm.expectEmit(true, true, true, true);
    emit RateFeedAdded(rateFeedID3);
    (uint256 tradingModeBefore, uint256 lastUpdatedTimeBefore, uint256 lastUpdatedBlockBefore) = breakerBox
      .rateFeedTradingModes(rateFeedID3);

    assert(tradingModeBefore == 0);
    assert(lastUpdatedTimeBefore == 0);
    assert(lastUpdatedBlockBefore == 0);

    skip(5);
    vm.roll(block.number + 1);
    breakerBox.addRateFeed(rateFeedID3);

    (uint256 tradingModeAfter, uint256 lastUpdatedTimeAfter, uint256 lastUpdatedBlockAfter) = breakerBox
      .rateFeedTradingModes(rateFeedID3);

    assert(tradingModeAfter == 0);
    assert(lastUpdatedTimeAfter > lastUpdatedTimeBefore);
    assert(lastUpdatedBlockAfter > lastUpdatedBlockBefore);
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
    breakerBox.setBreakerEnabled(address(mockBreaker1), rateFeedID1, true);
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker1), rateFeedID1), true);

    breakerBox.setRateFeedTradingMode(rateFeedID1, 1);
    vm.expectEmit(true, true, true, true);
    emit RateFeedRemoved(rateFeedID1);

    (uint256 tradingModeBefore, uint256 lastUpdatedTimeBefore, uint256 lastUpdatedBlockBefore) = breakerBox
      .rateFeedTradingModes(rateFeedID1);
    assert(tradingModeBefore == 1);
    assert(lastUpdatedTimeBefore > 0);
    assert(lastUpdatedBlockBefore > 0);

    breakerBox.removeRateFeed(rateFeedID1);

    (uint256 tradingModeAfter, uint256 lastUpdatedTimeAfter, uint256 lastUpdatedBlockAfter) = breakerBox
      .rateFeedTradingModes(rateFeedID1);
    assert(tradingModeAfter == 0);
    assert(lastUpdatedTimeAfter == 0);
    assert(lastUpdatedBlockAfter == 0);
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker1), rateFeedID3), false);
  }

  function test_setRateFeedTradingMode_whenRateFeedHasNotBeenAdded_ShouldRevert() public {
    vm.expectRevert("Rate feed ID has not been added");
    breakerBox.setRateFeedTradingMode(rateFeedID3, 1);
  }

  function test_setRateFeedTradingMode_whenSpecifiedTradingModeHasNoBreaker_ShouldRevert() public {
    vm.expectRevert("Trading mode must be default or have a breaker set");
    breakerBox.setRateFeedTradingMode(rateFeedID1, 9);
  }

  function test_setRateFeedTradingMode_whenUsingDefaultTradingMode_ShouldUpdateAndEmit() public {
    (uint256 tradingModeBefore, uint256 lastUpdatedTimeBefore, uint256 lastUpdatedBlockBefore) = breakerBox
      .rateFeedTradingModes(rateFeedID1);
    assert(tradingModeBefore == 0);
    assert(lastUpdatedTimeBefore > 0);
    assert(lastUpdatedBlockBefore > 0);

    //Fake time skip
    skip(5 * 60);
    vm.roll(5);
    vm.expectEmit(true, true, true, true);
    emit TradingModeUpdated(rateFeedID1, 1);

    breakerBox.setRateFeedTradingMode(rateFeedID1, 1);
    (uint256 tradingModeAfter, uint256 lastUpdatedTimeAfter, uint256 lastUpdatedBlockAfter) = breakerBox
      .rateFeedTradingModes(rateFeedID1);
    assert(tradingModeAfter == 1);
    assert(lastUpdatedTimeAfter > lastUpdatedTimeBefore);
    assert(lastUpdatedBlockAfter > lastUpdatedBlockBefore);
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
    setupBreakerAndRateFeed(mockBreaker3, 6, 3600, false, false, rateFeedID3);

    skip(3599);

    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectEmit(true, true, true, true);
    emit ResetAttemptNotCool(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(breakerBox.getRateFeedTradingMode(rateFeedID3), 6);
  }

  function test_checkAndSetBreakers_whenRateFeedIsNotInDefaultModeAndCantReset_shouldEmitCriteriaFail() public {
    setupBreakerAndRateFeed(mockBreaker3, 6, 3600, false, false, rateFeedID3);

    skip(3600);
    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.shouldReset.selector, rateFeedID3));
    vm.expectEmit(true, true, true, true);
    emit ResetAttemptCriteriaFail(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(breakerBox.getRateFeedTradingMode(rateFeedID3), 6);
  }

  function test_checkAndSetBreakers_whenRateFeedIsNotInDefaultModeAndCanReset_shouldResetMode() public {
    setupBreakerAndRateFeed(mockBreaker3, 6, 3600, true, false, rateFeedID3);
    skip(3600);

    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.shouldReset.selector, rateFeedID3));
    vm.expectEmit(true, true, true, true);
    emit ResetSuccessful(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(breakerBox.getRateFeedTradingMode(rateFeedID3), 0);
  }

  function test_checkAndSetBreakers_whenRateFeedIsNotInDefaultModeAndNoBreakerCooldown_shouldReturnCorrectModeAndEmit()
    public
  {
    setupBreakerAndRateFeed(mockBreaker3, 6, 0, true, false, rateFeedID3);
    skip(3600);

    vm.expectCall(address(mockBreaker3), abi.encodeWithSelector(mockBreaker3.getCooldown.selector));
    vm.expectEmit(true, true, true, true);
    emit ResetAttemptNotCool(rateFeedID3, address(mockBreaker3));

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(breakerBox.getRateFeedTradingMode(rateFeedID3), 6);
  }

  function test_checkAndSetBreakers_whenNoBreakersAreTripped_shouldReturnDefaultMode() public {
    setupBreakerAndRateFeed(mockBreaker3, 6, 3600, true, false, address(0));

    sortedOracles.addOracle(rateFeedID3, actor("oracleClient3"));
    breakerBox.addRateFeed(rateFeedID3);
    assertTrue(isRateFeed(rateFeedID3));

    breakerBox.setBreakerEnabled(address(mockBreaker3), rateFeedID3, true);
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker3), rateFeedID3), true);
    breakerBox.setBreakerEnabled(address(mockBreaker1), rateFeedID3, true);

    (uint256 tradingMode, , ) = breakerBox.rateFeedTradingModes(rateFeedID3);
    assertEq(tradingMode, 0);

    vm.expectCall(
      address(mockBreaker3),
      abi.encodeWithSelector(mockBreaker3.shouldTrigger.selector, address(rateFeedID3))
    );

    vm.expectCall(
      address(mockBreaker1),
      abi.encodeWithSelector(mockBreaker1.shouldTrigger.selector, address(rateFeedID3))
    );

    breakerBox.checkAndSetBreakers(rateFeedID3);
    assertEq(breakerBox.getRateFeedTradingMode(rateFeedID3), 0);
  }

  function test_checkAndSetBreakers_whenABreakerIsTripped_shouldSetModeAndEmit() public {
    setupBreakerAndRateFeed(mockBreaker3, 6, 3600, true, true, address(0));

    sortedOracles.addOracle(rateFeedID3, actor("oracleReport3"));
    breakerBox.addRateFeed(rateFeedID3);
    assertTrue(isRateFeed(rateFeedID3));

    breakerBox.setBreakerEnabled(address(mockBreaker3), rateFeedID3, true);
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker3), rateFeedID3), true);
    breakerBox.setBreakerEnabled(address(mockBreaker1), rateFeedID3, true);
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker1), rateFeedID3), true);

    (uint256 tradingMode, , ) = breakerBox.rateFeedTradingModes(rateFeedID3);
    assertEq(tradingMode, 0);

    vm.expectCall(
      address(mockBreaker1),
      abi.encodeWithSelector(mockBreaker1.shouldTrigger.selector, address(rateFeedID3))
    );

    vm.expectCall(
      address(mockBreaker3),
      abi.encodeWithSelector(mockBreaker3.shouldTrigger.selector, address(rateFeedID3))
    );

    vm.expectEmit(true, true, true, true);
    emit BreakerTripped(address(mockBreaker3), rateFeedID3);

    skip(3600);
    vm.roll(5);

    breakerBox.checkAndSetBreakers(rateFeedID3);

    (, uint256 lastUpdatedTime, uint256 lastUpdatedBlock) = breakerBox.rateFeedTradingModes(rateFeedID3);
    assertEq(lastUpdatedTime, 3601);
    assertEq(lastUpdatedBlock, 5);
  }

  function test_checkAndSetBreakers_whenABreakerIsNotEnabled_shouldNotTrigger() public {
    setupBreakerAndRateFeed(mockBreaker3, 6, 3600, true, true, address(0));

    // add rate feed
    sortedOracles.addOracle(rateFeedID3, actor("oracleReport3"));
    breakerBox.addRateFeed(rateFeedID3);
    assertTrue(isRateFeed(rateFeedID3));

    // disable it
    breakerBox.disableBreaker(address(mockBreaker3), rateFeedID3, false);
    assertEq(breakerBox.isBreakerEnabled(address(mockBreaker3), rateFeedID3), false);

    (uint256 tradingMode, , ) = breakerBox.rateFeedTradingModes(rateFeedID3);
    assertEq(tradingMode, 0);

    breakerBox.checkAndSetBreakers(rateFeedID3);

    skip(3600);
    vm.roll(5);

    (, uint256 lastUpdatedTime, uint256 lastUpdatedBlock) = breakerBox.rateFeedTradingModes(rateFeedID3);

    assertEq(lastUpdatedTime, 1);
    assertEq(lastUpdatedBlock, 1);
  }
}
