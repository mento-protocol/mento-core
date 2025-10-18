// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { TokenDeployer } from "test/integration/v3/TokenDeployer.sol";
import { FPMMDeployer } from "test/integration/v3/FPMMDeployer.sol";

import { StableTokenV3 } from "contracts/tokens/StableTokenV3.sol";

import { IBoldToken, IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

contract FPMMTest is TokenDeployer, FPMMDeployer {
  function test_integrationV3_fpmmTest() public {
    _deployTokens(false, false);
    _deployFPMM(false, false);
  }
}
