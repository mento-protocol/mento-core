// solhint-disable func-name-mixedcase
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { TestSetup } from "../TestSetup.sol";
import { MentoToken } from "contracts/governance/MentoToken.sol";

contract MentoToken_Test is TestSetup {
  MentoToken public mentoToken;

  address public vestingContract = makeAddr("vestingContract");
  address public airgrabContract = makeAddr("airgrabContract");
  address public treasuryContract = makeAddr("treasuryContract");
  address public emissionContract = makeAddr("emissionContract");

  function _newMentoToken() internal {
    mentoToken = new MentoToken(vestingContract, airgrabContract, treasuryContract, emissionContract);
  }
}
