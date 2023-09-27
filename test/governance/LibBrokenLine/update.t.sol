// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

import { console } from "forge-std-next/console.sol";
import { LibBrokenLine_Test } from "./Base.t.sol";
import { LibBrokenLine } from "contracts/governance/libs/LibBrokenLine.sol";

contract update_LibBrokenLine_Test is LibBrokenLine_Test {
  function _subject(LibBrokenLine.BrokenLine storage brokenLine, uint32 toTime) internal {
    LibBrokenLine.update(brokenLine, toTime);
  }

  function test_update_whenLineUpToDate_shouldNotUpdate() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    LibBrokenLine.Line memory initialBefore = brokenLine.initial;
    _subject(brokenLine, 1);
    LibBrokenLine.Line memory initialAfter = brokenLine.initial;
    assertLineEq(initialBefore, initialAfter);
  }

  function test_update_whenToTimeIsInPast_shouldRevert() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    vm.expectRevert("can't update BrokenLine for past time");
    _subject(brokenLine, 0);
  }

  function test_update_whenNegativeSlope_shouldRevert() public {
    uint96 slope = 10;
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, slope, 0);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    brokenLine.slopeChanges[1] = -(int96(slope) + 1);
    vm.expectRevert("slope < 0, something wrong with slope");
    _subject(brokenLine, 2);
  }

  function test_update_whenToTimeInCliffPeriod_shouldUpdateOnlyStart() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    _subject(brokenLine, 3);
    assertEq(brokenLine.initial.bias, 100);
    assertEq(brokenLine.initial.slope, 0);
    assertEq(brokenLine.initial.start, 3);
  }

  function test_update_whenToTimeInSlopePeriod_shouldSetAndAppySlope() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    _subject(brokenLine, 5);
    assertEq(brokenLine.initial.bias, 90);
    assertEq(brokenLine.initial.slope, 10);
    assertEq(brokenLine.initial.start, 5);
  }

  function test_update_whenToTimeInReminderPeriod_shouldSetAndAppySlope() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    _subject(brokenLine, 14);
    assertEq(brokenLine.initial.bias, 2);
    assertEq(brokenLine.initial.slope, 2);
    assertEq(brokenLine.initial.start, 14);
  }

  function test_update_whenToTimeInEndPeriod_shouldSetAndAppySlope() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    _subject(brokenLine, 15);
    assertEq(brokenLine.initial.bias, 0);
    assertEq(brokenLine.initial.slope, 0);
    assertEq(brokenLine.initial.start, 15);
  }

  function test_update_whenMultipleLines_shouldSetAndAppySlope() public {
    //Line(start, bias, slope, cliff)
    uint32 otherStart = 1;
    uint96 otherBias = 200;
    uint96 otherSlope = 10;
    uint32 otherCliff = 0;
    LibBrokenLine.Line memory line = LibBrokenLine.Line(otherStart, otherBias, otherSlope, otherCliff);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    uint32 testeeStart = 1;
    uint96 testeeBias = 102;
    uint96 testeeSlope = 10;
    uint32 testeeCliff = 3;
    LibBrokenLine.Line memory testee = LibBrokenLine.Line(testeeStart, testeeBias, testeeSlope, testeeCliff);
    LibBrokenLine.addOneLine(brokenLine, 1, testee, blockNumber());

    uint32 index;
    uint96 newBias = otherBias + testeeBias;
    for (uint32 i = 2; i <= testeeStart + testeeCliff + testeeBias / testeeSlope; i++) {
      newBias = newBias - otherSlope;
      if (i > testeeStart + testeeCliff) {
        //testee cliff period has ended
        newBias = newBias - testeeSlope;
      }
      _subject(brokenLine, i);

      assertEq(brokenLine.initial.bias, newBias);
      index = i;
    }

    //testee reminder period of bias % slope
    newBias = newBias - (testeeBias % testeeSlope) - otherSlope;
    _subject(brokenLine, index + 1);
    assertEq(brokenLine.initial.bias, newBias);
  }
}
