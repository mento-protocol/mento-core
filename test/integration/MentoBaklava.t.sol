// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { PrecompileHandler } from "celo-foundry/PrecompileHandler.sol";
import { MentoBaseForkTest } from "./MentoBase.t.sol";
import { Chain } from "test/utils/Chain.sol";

contract MentoBaklavaForkTest is MentoBaseForkTest {
  function setUp() public {
    Chain.fork(62320);
    ph = new PrecompileHandler();
    super.setUp();
  }
}