// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

contract Initializable {
  bool public initialized;

  constructor(bool testingDeployment) {
    if (!testingDeployment) {
      initialized = true;
    }
  }

  modifier initializer() {
    require(!initialized, "contract already initialized");
    initialized = true;
    _;
  }
}
