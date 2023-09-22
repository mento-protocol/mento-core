// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase
// solhint-disable contract-name-camelcase
import { MentoGovernor_Test } from "./Base.t.sol";

contract Init_MentoGovernor_Test is MentoGovernor_Test {
  function _subject() internal {
    _initMentoGovernor();
  }

  function test_init_shouldSetState() public {
    _subject();

    assertEq(mentoGovernor.votingDelay(), BLOCKS_DAY);
    assertEq(mentoGovernor.votingPeriod(), BLOCKS_WEEK);
    assertEq(mentoGovernor.proposalThreshold(), 1_000e18);
    assertEq(timelockController.getMinDelay(), 1 days);
  }
}
