// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "openzeppelin-contracts-v4.9.5/contracts/token/ERC20/IERC20.sol";
import { IBoldToken } from "contracts/v3/Interfaces/IBoldToken.sol";
import { ICollateralRegistry } from "contracts/v3/Interfaces/ICollateralRegistry.sol";
import { IWETH } from "contracts/v3/Interfaces/IWETH.sol";
import { HintHelpers } from "contracts/v3/HintHelpers.sol";
import { TestDeployer } from "./Deployment.t.sol";

contract BaseMultiCollateralTest {
  struct Contracts {
    IWETH weth;
    ICollateralRegistry collateralRegistry;
    IBoldToken boldToken;
    HintHelpers hintHelpers;
    TestDeployer.LiquityContractsDev[] branches;
  }

  IERC20 weth;
  ICollateralRegistry collateralRegistry;
  IBoldToken boldToken;
  HintHelpers hintHelpers;
  TestDeployer.LiquityContractsDev[] branches;

  function setupContracts(Contracts memory contracts) internal {
    weth = contracts.weth;
    collateralRegistry = contracts.collateralRegistry;
    boldToken = contracts.boldToken;
    hintHelpers = contracts.hintHelpers;

    for (uint256 i = 0; i < contracts.branches.length; ++i) {
      branches.push(contracts.branches[i]);
    }
  }
}
