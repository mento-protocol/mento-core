// SPDX-License-Identifier: UNLICENSED
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
  address referenceRateID1;
  address referenceRateID2;
  address referenceRateID3;
  address rando;

  MockBreaker mockBreakerA;
  MockBreaker mockBreakerB;
  MockBreaker mockBreakerC;
  MockBreaker mockBreakerD;
  BreakerBox breakerBox;
  MockSortedOracles sortedOracles;


  event BreakerAdded(address indexed breaker);
  event BreakerRemoved(address indexed breaker);
  event BreakerTripped(address indexed breaker, address indexed referenceRateID);
  event TradingModeUpdated(address indexed referenceRateID, uint256 tradingMode);
  event ResetSuccessful(address indexed referenceRateID, address indexed breaker);
  event ResetAttemptCriteriaFail(address indexed referenceRateID, address indexed breaker);
  event ResetAttemptNotCool(address indexed referenceRateID, address indexed breaker);
  event ReferenceRateIDAdded(address indexed referenceRate);
  event ReferenceRateIDRemoved(address indexed referenceRate);

  function setUp() public {
    deployer = actor("deployer");
    referenceRateID1 = actor("referenceRatDID1");
    referenceRateID2 = actor("referenceRateID2");
    referenceRateID3 = actor("referenceRateID3");
    rando = actor("rando");

    address[] memory testReferenceRateIDs = new address[](2);
    testReferenceRateIDs[0] = referenceRateID1;
    testReferenceRateIDs[1] = referenceRateID2;

    changePrank(deployer);
    mockBreakerA = new MockBreaker(0, false, false);
    mockBreakerB = new MockBreaker(0, false, false);
    mockBreakerC = new MockBreaker(0, false, false);
    mockBreakerD = new MockBreaker(0, false, false);
    sortedOracles = new MockSortedOracles();
    breakerBox = new BreakerBox(true);

    sortedOracles.addOracle(referenceRateID1, actor("oracleClient1"));
    sortedOracles.addOracle(referenceRateID2, actor("oracleClient1"));

    breakerBox.initialize(testReferenceRateIDs, ISortedOracles(address(sortedOracles)));
    // breakerBox.addBreaker(address(mockBreakerA), 1);
  }

  function isReferenceRateID(address referenceRateID) public view returns (bool referenceRateIDFound) {
    address[] memory allreferenceRateIDs = breakerBox.getReferenceRateIDs();
    for (uint256 i = 0; i < allreferenceRateIDs.length; i++) {
      if (allreferenceRateIDs[i] == referenceRateID) {
        referenceRateIDFound = true;
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
   * @param referenceRateID If referenceRateID is set, switch referenceRateID to the given trading mode
   */
  function setupBreakerAndReferenceRate(
    MockBreaker breaker,
    uint64 tradingMode,
    uint256 cooldown,
    bool reset,
    bool trigger,
    address referenceRateID
  ) public {
    vm.mockCall(
      address(breaker),
      abi.encodeWithSelector(breaker.getCooldown.selector),
      abi.encode(cooldown)
    );

    vm.mockCall(
      address(breaker),
      abi.encodeWithSelector(breaker.shouldReset.selector),
      abi.encode(reset)
    );

    vm.mockCall(
      address(breaker),
      abi.encodeWithSelector(breaker.shouldTrigger.selector),
      abi.encode(trigger)
    );

    breakerBox.addBreaker(address(breaker), tradingMode);
    assertTrue(breakerBox.isBreaker(address(breaker)));

    if (referenceRateID != address(0)) {
      breakerBox.addReferenceRate(referenceRateID);
      assertTrue(isReferenceRateID(referenceRateID));

      breakerBox.setReferenceRateTradingMode(referenceRateID, tradingMode);
      (uint256 savedTradingMode, , ) = breakerBox.referenceRateTradingModes(referenceRateID);
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
    assert(breakerBox.tradingModeBreaker(1) == address(mockBreakerA));
    assert(breakerBox.breakerTradingMode(address(mockBreakerA)) == 1);
    assert(breakerBox.isBreaker(address(mockBreakerA)));
  }

  // function test_initilize_shouldSetSortedOracles() public {
  //   assertEq(address(breakerBox.sortedOracles()), ISortedOracles(address(sortedOracles)));
  // }

  function test_initilize_shouldAddReferenceRateIDsWithDefaultMode() public view {
    (uint256 tradingModeA, uint256 lastUpdatedA, uint256 lastUpdatedBlockA) = breakerBox
      .referenceRateTradingModes(referenceRateID1);
    assert(tradingModeA == 0);
    assert(lastUpdatedA > 0);
    assert(lastUpdatedBlockA > 0);

    (uint256 tradingModeB, uint256 lastUpdatedB, uint256 lastUpdatedBlockB) = breakerBox
      .referenceRateTradingModes(referenceRateID2);
    assert(tradingModeB == 0);
    assert(lastUpdatedB > 0);
    assert(lastUpdatedBlockB > 0);
  }

  /* ---------- Breakers ---------- */

  function test_addBreaker_canOnlyBeCalledByOwner() public {
    vm.expectRevert("Ownable: caller is not the owner");
    changePrank(rando);
    breakerBox.addBreaker(address(mockBreakerA), 2);
  }

  function test_addBreaker_whenAddingDuplicateBreaker_shouldRevert() public {
    vm.expectRevert("This breaker has already been added");
    breakerBox.addBreaker(address(mockBreakerA), 2);
  }

  function test_addBreaker_whenAddingBreakerWithDuplicateTradingMode_shouldRevert() public {
    vm.expectRevert("There is already a breaker added with the same trading mode");
    breakerBox.addBreaker(address(mockBreakerB), 1);
  }

  function test_addBreaker_whenAddingBreakerWithDefaultTradingMode_shouldRevert() public {
    vm.expectRevert("The default trading mode can not have a breaker");
    breakerBox.addBreaker(address(mockBreakerB), 0);
  }

  function test_addBreaker_shouldUpdateAndEmit() public {
    vm.expectEmit(true, false, false, false);
    emit BreakerAdded(address(mockBreakerB));

    breakerBox.addBreaker(address(mockBreakerB), 2);

    assert(breakerBox.tradingModeBreaker(2) == address(mockBreakerB));
    assert(breakerBox.breakerTradingMode(address(mockBreakerB)) == 2);
    assert(breakerBox.isBreaker(address(mockBreakerB)));
  }

  function test_removeBreaker_whenBreakerHasntBeenAdded_shouldRevert() public {
    vm.expectRevert("This breaker has not been added");
    breakerBox.removeBreaker(address(mockBreakerB));
  }

  function test_removeBreaker_whenBreakerTradingModeInUse_shouldSetDefaultMode() public {
    breakerBox.addBreaker(address(mockBreakerC), 3);
    breakerBox.addReferenceRate(referenceRateID3);
    breakerBox.setReferenceRateTradingMode(referenceRateID3, 3);

    (uint256 tradingModeBefore, , ) = breakerBox.referenceRateTradingModes(referenceRateID3);
    assertEq(tradingModeBefore, 3);

    breakerBox.removeBreaker(address(mockBreakerC));

    (uint256 tradingModeAfter, , ) = breakerBox.referenceRateTradingModes(referenceRateID3);
    assertEq(tradingModeAfter, 0);
  }

  function test_removeBreaker_shouldUpdateStorageAndEmit() public {
    vm.expectEmit(true, false, false, false);
    emit BreakerRemoved(address(mockBreakerA));

    assert(breakerBox.tradingModeBreaker(1) == address(mockBreakerA));
    assert(breakerBox.breakerTradingMode(address(mockBreakerA)) == 1);
    assert(breakerBox.isBreaker(address(mockBreakerA)));

    breakerBox.removeBreaker(address(mockBreakerA));

    assert(breakerBox.tradingModeBreaker(1) == address(0));
    assert(breakerBox.breakerTradingMode(address(mockBreakerA)) == 0);
    assert(!breakerBox.isBreaker(address(mockBreakerA)));
  }

  function test_insertBreaker_whenBreakerHasAlreadyBeenAdded_shouldRevert() public {
    vm.expectRevert("This breaker has already been added");
    breakerBox.insertBreaker(address(mockBreakerA), 1, address(0), address(0));
  }

  function test_insertBreaker_whenAddingBreakerWithDuplicateTradingMode_shouldRevert() public {
    vm.expectRevert("There is already a breaker added with the same trading mode");
    breakerBox.insertBreaker(address(mockBreakerB), 1, address(0), address(0));
  }

  function test_insertBreaker_shouldInsertBreakerAtCorrectPositionAndEmit() public {
    assert(breakerBox.getBreakers().length == 1);

    breakerBox.addBreaker(address(mockBreakerB), 2);
    breakerBox.addBreaker(address(mockBreakerC), 3);

    address[] memory breakersBefore = breakerBox.getBreakers();
    assert(breakersBefore.length == 3);
    assert(breakersBefore[0] == address(mockBreakerA));
    assert(breakersBefore[1] == address(mockBreakerB));
    assert(breakersBefore[2] == address(mockBreakerC));

    vm.expectEmit(true, false, false, false);
    emit BreakerAdded(address(mockBreakerD));

    breakerBox.insertBreaker(
      address(mockBreakerD),
      4,
      address(mockBreakerB),
      address(mockBreakerA)
    );

    address[] memory breakersAfter = breakerBox.getBreakers();
    assert(breakersAfter.length == 4);
    assert(breakersAfter[0] == address(mockBreakerA));
    assert(breakersAfter[1] == address(mockBreakerD));
    assert(breakersAfter[2] == address(mockBreakerB));
    assert(breakersAfter[3] == address(mockBreakerC));

    assert(breakerBox.tradingModeBreaker(4) == address(mockBreakerD));
    assert(breakerBox.tradingModeBreaker(3) == address(mockBreakerC));
    assert(breakerBox.tradingModeBreaker(2) == address(mockBreakerB));
    assert(breakerBox.tradingModeBreaker(1) == address(mockBreakerA));

    assert(breakerBox.breakerTradingMode(address(mockBreakerD)) == 4);
  }

  /* ---------- Reference Rate IDs ---------- */

  function test_addReferenceRate_whenAlreadyAdded_shouldRevert() public {
    vm.expectRevert("Reference rate ID has already been added");
    breakerBox.addReferenceRate(referenceRateID1);
  }

  function test_addReferenceRate_whenReferenceRateDoesNotExistInOracleList_shouldRevert() public {
    vm.expectRevert("Reference rate does not exist in oracles list");
    breakerBox.addReferenceRate(referenceRateID3);
  }

  function test_addReferenceRate_whenReferenceRateExistsInOracleList_shouldSetDefaultModeAndEmit() public {
    sortedOracles.addOracle(referenceRateID3, actor("oracleAddress"));
    vm.expectEmit(true, true, true, true);
    emit ReferenceRateIDAdded(referenceRateID3);

    (uint256 tradingModeBefore, uint256 lastUpdatedTimeBefore, uint256 lastUpdatedBlockBefore) = breakerBox
      .referenceRateTradingModes(referenceRateID3);

    assert(tradingModeBefore == 0);
    assert(lastUpdatedTimeBefore == 0);
    assert(lastUpdatedBlockBefore == 0);

    skip(5);
    vm.roll(block.number + 1);
    breakerBox.addReferenceRate(referenceRateID3);

    (uint256 tradingModeAfter, uint256 lastUpdatedTimeAfter, uint256 lastUpdatedBlockAfter) = breakerBox
      .referenceRateTradingModes(referenceRateID3);

    assert(tradingModeAfter == 0);
    assert(lastUpdatedTimeAfter > lastUpdatedTimeBefore);
    assert(lastUpdatedBlockAfter > lastUpdatedBlockBefore);
  }

  function test_removeReferenceRate_whenReferenceRateHasNotBeenAdded_shouldRevert() public {
    vm.expectRevert("Reference rate ID has not been added");
    breakerBox.removeReferenceRate(referenceRateID3);
  }

  function test_removeReferenceRate_shouldRemoveReferenceRateFromArray() public {
    assertTrue(isReferenceRateID(referenceRateID1));
    breakerBox.removeReferenceRate(referenceRateID1);
    assertFalse(isReferenceRateID(referenceRateID1));
  }

  function test_removeReferenceRate_shouldResetTradingModeInfoAndEmit() public {
    breakerBox.setReferenceRateTradingMode(referenceRateID1, 1);
    vm.expectEmit(true, true, true, true);
    emit ReferenceRateIDRemoved(referenceRateID1);

    (uint256 tradingModeBefore, uint256 lastUpdatedTimeBefore, uint256 lastUpdatedBlockBefore) = breakerBox
      .referenceRateTradingModes(referenceRateID1);
    assert(tradingModeBefore == 1);
    assert(lastUpdatedTimeBefore > 0);
    assert(lastUpdatedBlockBefore > 0);

    breakerBox.removeReferenceRate(referenceRateID1);

    (uint256 tradingModeAfter, uint256 lastUpdatedTimeAfter, uint256 lastUpdatedBlockAfter) = breakerBox
      .referenceRateTradingModes(referenceRateID1);
    assert(tradingModeAfter == 0);
    assert(lastUpdatedTimeAfter == 0);
    assert(lastUpdatedBlockAfter == 0);
  }

  function test_setReferenceRateTradingMode_whenReferenceRateHasNotBeenAdded_ShouldRevert() public {
    vm.expectRevert("Reference rate ID has not been added");
    breakerBox.setReferenceRateTradingMode(referenceRateID3, 1);
  }

  function test_setReferenceRateTradingMode_whenSpecifiedTradingModeHasNoBreaker_ShouldRevert() public {
    vm.expectRevert("Trading mode must be default or have a breaker set");
    breakerBox.setReferenceRateTradingMode(referenceRateID1, 9);
  }

  function test_setReferenceRateTradingMode_whenUsingDefaultTradingMode_ShouldUpdateAndEmit() public {
    (uint256 tradingModeBefore, uint256 lastUpdatedTimeBefore, uint256 lastUpdatedBlockBefore) = breakerBox
      .referenceRateTradingModes(referenceRateID1);
    assert(tradingModeBefore == 0);
    assert(lastUpdatedTimeBefore > 0);
    assert(lastUpdatedBlockBefore > 0);

    //Fake time skip
    skip(5 * 60);
    vm.roll(5);
    vm.expectEmit(true, true, true, true);
    emit TradingModeUpdated(referenceRateID1, 1);

    breakerBox.setReferenceRateTradingMode(referenceRateID1, 1);
    (uint256 tradingModeAfter, uint256 lastUpdatedTimeAfter, uint256 lastUpdatedBlockAfter) = breakerBox
      .referenceRateTradingModes(referenceRateID1);
    assert(tradingModeAfter == 1);
    assert(lastUpdatedTimeAfter > lastUpdatedTimeBefore);
    assert(lastUpdatedBlockAfter > lastUpdatedBlockBefore);
  }
}

// contract BreakerBoxTest_checkAndSetBreakers is BreakerBoxTest {
//   function test_checkAndSetBreakers_whenExchangeIsNotInDefaultModeAndCooldownNotPassed_shouldEmitNotCool()
//     public
//   {
//     setupBreakerAndExchange(mockBreakerC, 6, 3600, false, false, referenceRateID3);

//     skip(3599);

//     vm.expectCall(address(mockBreakerC), abi.encodeWithSelector(mockBreakerC.getCooldown.selector));
//     vm.expectEmit(true, true, false, false);
//     emit ResetAttemptNotCool(referenceRateID3, address(mockBreakerC));

//     breakerBox.checkAndSetBreakers(actor("oracleReportTarget"));
//     assertEq(breakerBox.getTradingMode(referenceRateID3), 6);
//   }

//   function test_checkAndSetBreakers_whenExchangeIsNotInDefaultModeAndCantReset_shouldEmitCriteriaFail()
//     public
//   {
//     setupBreakerAndExchange(mockBreakerC, 6, 3600, false, false, referenceRateID3);

//     skip(3600);
//     vm.expectCall(address(mockBreakerC), abi.encodeWithSelector(mockBreakerC.getCooldown.selector));
//     vm.expectCall(
//       address(mockBreakerC),
//       abi.encodeWithSelector(mockBreakerC.shouldReset.selector, referenceRateID3)
//     );
//     vm.expectEmit(true, true, false, false);
//     emit ResetAttemptCriteriaFail(referenceRateID3, address(mockBreakerC));

//     breakerBox.checkAndSetBreakers(actor("oracleReportTarget"));
//     assertEq(breakerBox.getTradingMode(referenceRateID3), 6);
//   }

//   function test_checkAndSetBreakers_whenExchangeIsNotInDefaultModeAndCanReset_shouldResetMode()
//     public
//   {
//     setupBreakerAndExchange(mockBreakerC, 6, 3600, true, false, referenceRateID3);
//     skip(3600);

//     vm.expectCall(address(mockBreakerC), abi.encodeWithSelector(mockBreakerC.getCooldown.selector));
//     vm.expectCall(
//       address(mockBreakerC),
//       abi.encodeWithSelector(mockBreakerC.shouldReset.selector, referenceRateID3)
//     );
//     vm.expectEmit(true, true, false, false);
//     emit ResetSuccessful(referenceRateID3, address(mockBreakerC));

//     breakerBox.checkAndSetBreakers(actor("oracleReportTarget"));
//     assertEq(breakerBox.getTradingMode(referenceRateID3), 0);
//   }

//   function test_checkAndSetBreakers_whenExchangeIsNotInDefaultModeAndNoBreakerCooldown_shouldReturnCorrectModeAndEmit()
//     public
//   {
//     setupBreakerAndExchange(mockBreakerC, 6, 0, true, false, referenceRateID3);
//     skip(3600);

//     vm.expectCall(address(mockBreakerC), abi.encodeWithSelector(mockBreakerC.getCooldown.selector));
//     vm.expectEmit(true, true, false, false);
//     emit ResetAttemptNotCool(referenceRateID3, address(mockBreakerC));

//     breakerBox.checkAndSetBreakers(actor("oracleReportTarget"));
//     assertEq(breakerBox.getTradingMode(referenceRateID3), 6);
//   }

//   function test_checkAndSetBreakers_whenNoBreakersAreTripped_shouldReturnDefaultMode() public {
//     setupBreakerAndExchange(mockBreakerC, 6, 3600, true, false, address(0));
//     breakerBox.addReferenceRate(referenceRateID3);
//     assertTrue(isReferenceRateID(referenceRateID3));

//     (uint256 tradingMode, , ) = breakerBox.referenceRateTradingModes(referenceRateID3);
//     assertEq(tradingMode, 0);

//     vm.expectCall(
//       address(mockBreakerC),
//       abi.encodeWithSelector(mockBreakerC.shouldTrigger.selector, address(referenceRateID3))
//     );
//     vm.expectCall(
//       address(mockBreakerA),
//       abi.encodeWithSelector(mockBreakerA.shouldTrigger.selector, address(referenceRateID3))
//     );

//     breakerBox.checkAndSetBreakers(actor("oracleReportTarget"));
//     assertEq(breakerBox.getTradingMode(referenceRateID3), 0);
//   }

//   function test_checkAndSetBreakers_whenABreakerIsTripped_shouldSetModeAndEmit() public {
//     setupBreakerAndExchange(mockBreakerC, 6, 3600, true, true, address(0));

//     breakerBox.addReferenceRate(referenceRateID3);
//     assertTrue(isReferenceRateID(referenceRateID3));

//     (uint256 tradingMode, , ) = breakerBox.referenceRateTradingModes(referenceRateID3);
//     assertEq(tradingMode, 0);

//     vm.expectCall(
//       address(mockBreakerA),
//       abi.encodeWithSelector(mockBreakerA.shouldTrigger.selector, address(referenceRateID3))
//     );

//     vm.expectCall(
//       address(mockBreakerC),
//       abi.encodeWithSelector(mockBreakerC.shouldTrigger.selector, address(referenceRateID3))
//     );

//     vm.expectEmit(true, true, false, false);
//     emit BreakerTripped(address(mockBreakerC), referenceRateID3);

//     skip(3600);
//     vm.roll(5);

//     breakerBox.checkAndSetBreakers(actor("oracleReportTarget"));

//     (, uint256 lastUpdatedTime, uint256 lastUpdatedBlock) = breakerBox.referenceRateTradingModes(
//       referenceRateID3
//     );
//     assertEq(lastUpdatedTime, 3601);
//     assertEq(lastUpdatedBlock, 5);
//   }
// }