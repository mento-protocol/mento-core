// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { BaseForkTest } from "./BaseForkTest.t.sol";

contract BaklavaForkTest is BaseForkTest(62320) {}
contract AlfajoresForkTest is BaseForkTest(44787) {}
contract CeloMainnetForkTest is BaseForkTest(42220) {}