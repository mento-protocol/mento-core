// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

import { console } from "forge-std-next/console.sol";
import { LibBrokenLine_Test } from "./Base.t.sol";
import { LibBrokenLine } from "contracts/governance/libs/LibBrokenLine.sol";

contract actualValue_LibBrokenLine_Test is LibBrokenLine_Test {
  function _subject(
    LibBrokenLine.BrokenLine storage brokenLine,
    uint32 toTime,
    uint32 toBlock
  ) internal view returns (uint96 bias) {
    return LibBrokenLine.actualValue(brokenLine, toTime, toBlock);
  }

  function test_actualValue_whenToTimeInPastAndInCliffPeriod_shouldReturnBias() public {
    uint256 initialBlock = 100;
    vm.roll(initialBlock);
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    vm.roll(initialBlock + 50);
    LibBrokenLine.update(brokenLine, 20);

    uint96 bias = _subject(brokenLine, 1, uint32(initialBlock));
    assertEq(bias, 100);
  }

  function test_actualValue_whenToTimeInPastAndInSlopePeriod_shouldReturnCorrectValue() public {
    uint256 initialBlock = 100;
    vm.roll(initialBlock);

    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    vm.roll(initialBlock + 50);
    LibBrokenLine.update(brokenLine, 5);
    uint96 actualBias = brokenLine.initial.bias;

    vm.roll(initialBlock + 100);
    LibBrokenLine.update(brokenLine, 20);

    uint96 bias = _subject(brokenLine, 5, uint32(initialBlock + 50));
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeInPastAndInReminderPeriod_shouldReturnReminder() public {
    uint256 initialBlock = 100;
    vm.roll(initialBlock);

    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    vm.roll(initialBlock + 50);
    LibBrokenLine.update(brokenLine, 14);
    uint96 actualBias = brokenLine.initial.bias;

    vm.roll(initialBlock + 100);
    LibBrokenLine.update(brokenLine, 20);

    uint96 bias = _subject(brokenLine, 14, uint32(initialBlock + 50));
    assertEq(bias, 2);
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeInPastAndInFinishedPeriod_shouldReturnZero() public {
    uint256 initialBlock = 100;
    vm.roll(initialBlock);

    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    vm.roll(initialBlock + 50);
    LibBrokenLine.update(brokenLine, 16);
    uint96 actualBias = brokenLine.initial.bias;

    vm.roll(initialBlock + 100);
    LibBrokenLine.update(brokenLine, 20);

    uint96 bias = _subject(brokenLine, 16, uint32(initialBlock + 50));
    assertEq(bias, 0);
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeIsNowAndInCliffPeriod_shouldReturnBias() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    uint96 bias = _subject(brokenLine, 1, blockNumber());
    uint96 actualBias = brokenLine.initial.bias;
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeIsBeforeLineStart_shouldReturnZero() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(2, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 5, line, blockNumber());

    uint96 bias = _subject(brokenLine, 1, blockNumber() - 1);
    uint96 actualBias = 0;
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeIsNowAndInSlopePeriod_shouldReturnCorrectValue() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());
    LibBrokenLine.update(brokenLine, 5);

    uint96 bias = _subject(brokenLine, 5, blockNumber());
    uint96 actualBias = brokenLine.initial.bias;
    assertEq(actualBias, 90);
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeIsNowAndInReminderWeek_shouldReturnReminder() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());
    LibBrokenLine.update(brokenLine, 14);

    uint96 bias = _subject(brokenLine, 14, blockNumber());
    uint96 actualBias = brokenLine.initial.bias;
    assertEq(actualBias, 102 % 10);
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeIsNowAndInFinishedPeriod_shouldReturnZero() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());
    LibBrokenLine.update(brokenLine, 15);

    uint96 bias = _subject(brokenLine, 15, blockNumber());
    uint96 actualBias = brokenLine.initial.bias;
    assertEq(actualBias, 0);
    assertEq(bias, actualBias);
  }

  function test_actualValue_whenToTimeInFutureAndInCliffPeriod_shouldReturnBias() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    uint96 bias = _subject(brokenLine, 3, blockNumber());
    uint96 expectedBias = brokenLine.initial.bias;
    assertEq(expectedBias, 100);
    assertEq(bias, expectedBias);
  }

  function test_actualValue_whenToTimeInFutureAndInSlopePeriod_shouldReturnCorrectValue() public {
    uint32 start = 1;
    uint96 bias = 100;
    uint96 slope = 10;
    uint32 cliff = 3;
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(start, bias, slope, cliff);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    for (uint256 i = 1; i <= bias / slope; i++) {
      uint32 toTime = start + cliff + uint32(i);
      uint96 expectedBias = bias - slope * uint96(i);
      uint96 actualBias = _subject(brokenLine, toTime, blockNumber());
      assertEq(actualBias, expectedBias);
    }
  }

  function test_actualValue_whenToTimeInFutureAndInReminderWeek_shouldReturnReminder() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    uint96 bias = _subject(brokenLine, 14, blockNumber());
    uint96 expectedBias = 102 % 10;
    assertEq(bias, expectedBias);
  }

  function test_actualValue_whenToTimeInFutureAndInFinishedPeriod_shouldReturnZero() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 102, 10, 3);
    LibBrokenLine.addOneLine(brokenLine, 0, line, blockNumber());

    uint96 bias = _subject(brokenLine, 15, blockNumber());
    uint96 expectedBias = 0;
    assertEq(bias, expectedBias);
  }
}
