// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Actions } from "../actions/all.sol";

contract BaseAssertions {
  Actions public actions;

  constructor() {
    actions = new Actions();
  }
}
