// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
pragma experimental ABIEncoderV2;

import { console } from "forge-std-next/console.sol";
import { LibBrokenLine_Test } from "./Base.t.sol";
import { LibBrokenLine } from "contracts/governance/libs/LibBrokenLine.sol";

contract addOneLine_LibBrokenLine_Test is LibBrokenLine_Test {
  function _subject(
    LibBrokenLine.BrokenLine storage brokenLine,
    uint256 id,
    LibBrokenLine.Line memory line,
    uint32 blockNumber
  ) internal {
    LibBrokenLine.addOneLine(brokenLine, id, line, blockNumber);
  }

  function test_addOneLine_whenSlopeZero_shouldRevert() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 0, 3);
    vm.expectRevert("Slope == 0, unacceptable value for slope");
    _subject(brokenLine, 0, line, blockNumber());
  }

  function test_addOneLine_whenSlopeLargerThanBias_shouldRevert() public {
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 101, 3);
    vm.expectRevert("Slope > bias, unacceptable value for slope");
    _subject(brokenLine, 0, line, blockNumber());
  }

  function test_addOneLine_whenLineWithIdAlreadyAdded_shouldRevert() public {
    uint256 id = 0;
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory line = LibBrokenLine.Line(1, 100, 10, 3);
    _subject(brokenLine, id, line, blockNumber());
    vm.expectRevert("Line with given id is already exist");
    _subject(brokenLine, id, line, blockNumber());
  }

  function test_addOneLine_whenValidCall_shouldSaveSnapShot() public {
    // history should be empty
    assertEq(brokenLine.history.length, 0);

    uint256 id = 0;
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 100, 10, 3);
    _subject(brokenLine, id, firstLine, blockNumber());

    // verify point in history was saved correctly
    assertEq(brokenLine.history.length, 1);
    LibBrokenLine.Point memory point = brokenLine.history[0];
    assertEq(point.blockNumber, blockNumber());
    assertEq(point.bias, 100);
    assertEq(point.slope, 0);
    assertEq(point.epoch, 1);
  }

  function test_addOneLine_whenOnlyLine_shouldUpdateStruct() public {
    uint256 id = 0;

    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 100, 10, 3);
    _subject(brokenLine, id, firstLine, blockNumber());

    // verify line attributes were updated correctly
    LibBrokenLine.Line memory initialLine = brokenLine.initial;
    assertEq(initialLine.start, 1);
    assertEq(initialLine.bias, 100);
    assertEq(initialLine.slope, 0);
    assertLineEq(brokenLine.initiatedLines[id], firstLine);

    // verify slope changes were set correctly
    assertEq(brokenLine.slopeChanges[1], 0);
    assertEq(brokenLine.slopeChanges[3], 10); // after cliff ended slope starts at -10 per week
    assertEq(brokenLine.slopeChanges[13], -10); // once line ends, slope changes back to 0
  }

  function test_addOneLine_whenNoCliff_shouldSetSlope() public {
    uint256 id = 0;
    //Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 100, 10, 0);
    _subject(brokenLine, id, firstLine, blockNumber());

    // verify line attributes were updated correctly
    LibBrokenLine.Line memory initialLine = brokenLine.initial;
    assertEq(initialLine.start, 1);
    assertEq(initialLine.bias, 100);
    assertEq(initialLine.slope, 10);
    assertLineEq(brokenLine.initiatedLines[id], firstLine);

    // verify slope changes were set correctly
    assertEq(brokenLine.slopeChanges[10], -10); // once line ends, slope changes back to 0
  }

  function test_addOneLine_whenMultipleLines_shouldAggregateLines() public {
    // add first Line
    uint256 id1 = 0;
    // Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 100, 10, 2);
    _subject(brokenLine, id1, firstLine, blockNumber());

    // verify line attributes were updated correctly
    LibBrokenLine.Line memory initialLine = brokenLine.initial;
    assertEq(initialLine.start, 1);
    assertEq(initialLine.bias, 100);
    assertEq(initialLine.slope, 0);
    assertLineEq(brokenLine.initiatedLines[id1], firstLine);

    // add second Line
    uint256 id2 = 1;
    // Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory secondLine = LibBrokenLine.Line(1, 200, 20, 2);
    _subject(brokenLine, id2, secondLine, blockNumber());

    // verify line attributes were updated correctly
    initialLine = brokenLine.initial;
    assertEq(initialLine.start, 1);
    assertEq(initialLine.bias, 100 + 200);
    assertEq(initialLine.slope, 0);
    assertLineEq(brokenLine.initiatedLines[id2], secondLine);

    // verify slope changes were set correctly
    assertEq(brokenLine.slopeChanges[2], 10 + 20); // after both cliffs end slope starts at -30 per week
    assertEq(brokenLine.slopeChanges[12], -10 - 20); // once lines end, slope changes back to 0

    // jump to week 3
    LibBrokenLine.update(brokenLine, 3);

    // verify line attributes were updated correctly
    initialLine = brokenLine.initial;
    assertEq(initialLine.start, 3);
    assertEq(initialLine.bias, 100 + 200);
    assertEq(initialLine.slope, 10 + 20);
  }

  function test_addOneLine_whenBiasModSlopeIsNotZero_shouldSetAdditionalSlopeChanges() public {
    // add first line
    uint256 id1 = 0;
    // Line(start, bias, slope, cliff)
    LibBrokenLine.Line memory firstLine = LibBrokenLine.Line(1, 102, 10, 2);
    _subject(brokenLine, id1, firstLine, blockNumber());

    // verify line attributes were updated correctly
    LibBrokenLine.Line memory initialLine = brokenLine.initial;
    assertEq(initialLine.start, 1);
    assertEq(initialLine.bias, 102);
    assertEq(initialLine.slope, 0);
    assertLineEq(brokenLine.initiatedLines[id1], firstLine);

    // verify slope changes were set correctly
    assertEq(brokenLine.slopeChanges[2], 10); // after cliff ends slope starts at -10 per week
    assertEq(brokenLine.slopeChanges[12], -8); // Since 102%10 = 2, slope changes to -2 per week
    assertEq(brokenLine.slopeChanges[13], -2); // once line ends, slope changes back to 0
  }
}
