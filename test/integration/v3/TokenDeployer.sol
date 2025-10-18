// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";
import { console2 as console } from "forge-std/console2.sol";

contract TokenDeployer is TestStorage {
  bool private _collateralTokenDeployed;
  bool private _debtTokenDeployed;
  bool private _reserveCollateralTokenDeployed;

  function _deployTokens(bool isCollateralTokenToken0, bool isDebtTokenToken0) internal {
    address lowest = address(1001);
    address middle = address(1002);
    address highest = address(1003);

    if (!isCollateralTokenToken0 && !isDebtTokenToken0) {
      _deployReserveCollateralToken(lowest);
      _deployCollateralToken(middle);
      _deployDebtToken(highest);
    } else if (isCollateralTokenToken0 && isDebtTokenToken0) {
      _deployDebtToken(lowest);
      _deployCollateralToken(middle);
      _deployReserveCollateralToken(highest);
    } else if (isCollateralTokenToken0 && !isDebtTokenToken0) {
      _deployCollateralToken(lowest);
      _deployReserveCollateralToken(middle);
      _deployDebtToken(highest);
    } else if (!isCollateralTokenToken0 && isDebtTokenToken0) {
      _deployDebtToken(lowest);
      _deployReserveCollateralToken(middle);
      _deployCollateralToken(highest);
    }
    $tokens.deployed = true;
  }

  function _deployCollateralToken(address targetAddress) private {
    deployCodeTo("StableTokenV3.sol:StableTokenV3", abi.encode(false), targetAddress);

    uint256[] memory numbers = new uint256[](0);
    address[] memory addresses = new address[](0);
    IStableTokenV3(targetAddress).initialize(
      "Mento USD",
      "USD.m",
      $addresses.governance,
      addresses,
      numbers,
      addresses,
      addresses,
      addresses
    );
    $tokens.collateralToken = IStableTokenV3(targetAddress);
    vm.label(targetAddress, "CollateralToken");

    _collateralTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _deployDebtToken(address targetAddress) private {
    deployCodeTo("StableTokenV3.sol:StableTokenV3", abi.encode(false), targetAddress);

    uint256[] memory numbers = new uint256[](0);
    address[] memory addresses = new address[](0);
    IStableTokenV3(targetAddress).initialize(
      "Mento Euro",
      "EUR.m",
      $addresses.governance,
      addresses,
      numbers,
      addresses,
      addresses,
      addresses
    );
    $tokens.debtToken = IStableTokenV3(targetAddress);
    vm.label(targetAddress, "DebtToken");
    _debtTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _deployReserveCollateralToken(address targetAddress) private {
    deployCodeTo("out/MockERC20.sol/MockERC20.0.8.24.json", abi.encode("Circle USD", "USDC", 6), targetAddress);

    $tokens.reserveCollateralToken = IERC20Metadata(targetAddress);
    vm.label(targetAddress, "ReserveCollateralToken");
    _reserveCollateralTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _checkAllTokensDeployed() private {
    if (_collateralTokenDeployed && _debtTokenDeployed && _reserveCollateralTokenDeployed) {
      $tokens.deployed = true;
    }
  }

  function _mintReserveCollateralToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    MockERC20 reserveCollateralToken = MockERC20(address($tokens.reserveCollateralToken));

    uint256 balanceBefore = reserveCollateralToken.balanceOf(targetAddress);
    reserveCollateralToken.mint(targetAddress, amount);
    uint256 balanceAfter = reserveCollateralToken.balanceOf(targetAddress);

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint reserve collateral token failed");
  }

  function _mintCollateralToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    vm.startPrank(address($liquidityStrategies.reserveLiquidityStrategy));
    uint256 balanceBefore = $tokens.collateralToken.balanceOf(targetAddress);
    $tokens.collateralToken.mint(targetAddress, amount);
    uint256 balanceAfter = $tokens.collateralToken.balanceOf(targetAddress);
    vm.stopPrank();

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint collateral token failed");
  }
}
