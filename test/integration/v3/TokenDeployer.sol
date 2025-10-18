// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";
import { StableTokenV3 } from "contracts/tokens/StableTokenV3.sol";

contract TokenDeployer is TestStorage {
  bool private _collateralTokenDeployed;
  bool private _debtTokenDeployed;

  function _deployTokens() internal {
    _deployCollateralToken("Collateral Token", "COLL", 18);
    _deployDebtToken("Debt Token", "DEBT");
  }

  function _deployCollateralToken(string memory name, string memory symbol, uint8 decimals) internal {
    $tokens.collateralToken = IStableTokenV3(address(new MockERC20(name, symbol, decimals)));

    _collateralTokenDeployed = true;
    _checkIfBothDeployed();
  }

  function _deployDebtToken(string memory name, string memory symbol) internal {
    StableTokenV3 newDebtToken = new StableTokenV3(false);
    uint256[] memory numbers = new uint256[](0);
    address[] memory addresses = new address[](0);
    newDebtToken.initialize(name, symbol, addresses, numbers, addresses, addresses, addresses);
    $tokens.debtToken = newDebtToken;

    _debtTokenDeployed = true;
    _checkIfBothDeployed();
  }

  function _checkIfBothDeployed() private {
    if (_collateralTokenDeployed && _debtTokenDeployed) {
      $tokens.deployed = true;
    }
  }
}
