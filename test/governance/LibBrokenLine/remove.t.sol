// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

import { console } from "forge-std-next/console.sol";
import { LibBrokenLine_Test } from "./Base.t.sol";
import { LibBrokenLine } from "contracts/governance/libs/LibBrokenLine.sol";

contract remove_LibBrokenLine_Test is LibBrokenLine_Test {
  function _subject(
    LibBrokenLine.BrokenLine storage brokenLine,
    uint256 id,
    uint32 toTime,
    uint32 blockNumber
  )
    internal
    returns (
      uint96 bias,
      uint96 slope,
      uint32 cliff
    )
  {
    (bias, slope, cliff) = LibBrokenLine.remove(brokenLine, id, toTime, blockNumber);
  }

  function test_remove_whenLineDoesNotExist_shouldRevert() public {
    vm.expectRevert("Removing Line, which not exists");
    _subject(brokenLine, 0, 1, blockNumber());
  }

  function test_remove_whenValidCall_shouldSaveSnapshot() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    // history should have one entry from adding line
    assertEq(brokenLine.history.length, 1);

    _subject(brokenLine, 0, 1, blockNumber());

    // verify point in history was saved correctly
    assertEq(brokenLine.history.length, 2);
    LibBrokenLine.Point memory point = brokenLine.history[1];
    assertEq(point.blockNumber, blockNumber());
    assertEq(point.bias, 0);
    assertEq(point.slope, 0);
    assertEq(point.epoch, 1);
  }

  function test_remove_whenLineIsOutdated_shouldReturnZero() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());
    (uint96 bias, uint96 slope, uint32 cliff) = _subject(brokenLine, 0, 14, blockNumber());
    assertEq(bias, 0);
    assertEq(slope, 0);
    assertEq(cliff, 0);
  }

  function test_remove_whenInCLiffPeriod_shouldUpdateLineCorrectly() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 50, 5, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, firstLine, blockNumber());
    LibBrokenLine.Line memory secondLine = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 1, secondLine, blockNumber());

    int96 slopeChangeStart = brokenLine.slopeChanges[3];
    assertEq(slopeChangeStart, 15);
    int96 slopeChangeEnd = brokenLine.slopeChanges[13];
    assertEq(slopeChangeEnd, -13);
    int96 slopeChangeReminder = brokenLine.slopeChanges[14];
    assertEq(slopeChangeReminder, -2);

    (uint96 bias, uint96 slope, uint32 cliff) = _subject(brokenLine, 1, 3, blockNumber());
    //curren state of second Line
    assertEq(bias, 102);
    assertEq(slope, 10);
    assertEq(cliff, 1);

    //brokenLine state
    assertEq(brokenLine.initiatedLines[1].bias, 0);
    LibBrokenLine.Line memory initialLine = brokenLine.initial;
    assertEq(initialLine.bias, 50);
    assertEq(initialLine.slope, 0);

    //brokenLine slopeChanges
    assertEq(brokenLine.slopeChanges[3], slopeChangeStart - 10);
    assertEq(brokenLine.slopeChanges[13], slopeChangeEnd + 8);
    assertEq(brokenLine.slopeChanges[14], slopeChangeReminder + 2);
  }

  function test_remove_whenInSlopePeriod_shouldUpdateLineCorrectly() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 50, 5, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, firstLine, blockNumber());
    LibBrokenLine.Line memory secondLine = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 1, secondLine, blockNumber());

    int96 slopeChangeStart = brokenLine.slopeChanges[3];
    assertEq(slopeChangeStart, 15);
    int96 slopeChangeEnd = brokenLine.slopeChanges[13];
    assertEq(slopeChangeEnd, -13);
    int96 slopeChangeReminder = brokenLine.slopeChanges[14];
    assertEq(slopeChangeReminder, -2);

    (uint96 bias, uint96 slope, uint32 cliff) = _subject(brokenLine, 1, 5, blockNumber());
    //curren state of second Line
    assertEq(bias, 92);
    assertEq(slope, 10);
    assertEq(cliff, 0);

    //brokenLine state
    assertEq(brokenLine.initiatedLines[1].bias, 0);
    LibBrokenLine.Line memory initialLine = brokenLine.initial;
    assertEq(initialLine.bias, 45);
    assertEq(initialLine.slope, 5);

    //brokenLine slopeChanges
    assertEq(brokenLine.slopeChanges[13], slopeChangeEnd + 8);
    assertEq(brokenLine.slopeChanges[14], slopeChangeReminder + 2);
  }

  function test_remove_whenInReminderPeriod_shouldUpdateLineCorrectly() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 50, 5, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, firstLine, blockNumber());
    LibBrokenLine.Line memory secondLine = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 1, secondLine, blockNumber());

    int96 slopeChangeStart = brokenLine.slopeChanges[3];
    assertEq(slopeChangeStart, 15);
    int96 slopeChangeEnd = brokenLine.slopeChanges[13];
    assertEq(slopeChangeEnd, -13);
    int96 slopeChangeReminder = brokenLine.slopeChanges[14];
    assertEq(slopeChangeReminder, -2);

    (uint96 bias, uint96 slope, uint32 cliff) = _subject(brokenLine, 1, 14, blockNumber());
    //curren state of second Line
    assertEq(bias, 2);
    assertEq(slope, 2);
    assertEq(cliff, 0);

    //brokenLine state
    assertEq(brokenLine.initiatedLines[1].bias, 0);
    LibBrokenLine.Line memory initialLine = brokenLine.initial;
    assertEq(initialLine.bias, 0);
    assertEq(initialLine.slope, 0);

    //brokenLine slopeChanges
    assertEq(brokenLine.slopeChanges[14], slopeChangeReminder + 2);
  }
}
