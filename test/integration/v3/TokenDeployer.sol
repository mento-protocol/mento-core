// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";

contract TokenDeployer is TestStorage {
  bool private _resDebtTokenDeployed;
  bool private _cdpDebtTokenDeployed;
  bool private _resCollTokenDeployed;

  function _deployTokens(bool isCollateralTokenToken0, bool isDebtTokenToken0) internal {
    address lowest = address(1001);
    address middle = address(1002);
    address highest = address(1003);

    if (!isCollateralTokenToken0 && !isDebtTokenToken0) {
      _deployReserveCollToken(lowest);
      _deployReserveDebtToken(middle);
      _deployCDPDebtToken(highest);
    } else if (isCollateralTokenToken0 && isDebtTokenToken0) {
      _deployCDPDebtToken(lowest);
      _deployReserveDebtToken(middle);
      _deployReserveCollToken(highest);
    } else if (isCollateralTokenToken0 && !isDebtTokenToken0) {
      _deployReserveDebtToken(lowest);
      _deployReserveCollToken(middle);
      _deployCDPDebtToken(highest);
    } else if (!isCollateralTokenToken0 && isDebtTokenToken0) {
      _deployCDPDebtToken(lowest);
      _deployReserveCollToken(middle);
      _deployReserveDebtToken(highest);
    }
    $tokens.deployed = true;
  }

  function _deployReserveDebtToken(address targetAddress) private {
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
    $tokens.resDebtToken = IStableTokenV3(targetAddress);
    $tokens.cdpCollToken = IStableTokenV3(targetAddress);
    vm.label(targetAddress, "USD.m");

    _resDebtTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _deployCDPDebtToken(address targetAddress) private {
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
    $tokens.cdpDebtToken = IStableTokenV3(targetAddress);
    vm.label(targetAddress, "EUR.m");
    _cdpDebtTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _deployReserveCollToken(address targetAddress) private {
    deployCodeTo("out/MockERC20.sol/MockERC20.0.8.24.json", abi.encode("Circle USD", "USDC", 6), targetAddress);

    $tokens.resCollToken = IERC20Metadata(targetAddress);
    vm.label(targetAddress, "USDC");
    _resCollTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _checkAllTokensDeployed() private {
    if (_resDebtTokenDeployed && _cdpDebtTokenDeployed && _resCollTokenDeployed) {
      $tokens.deployed = true;
    }
  }

  function _mintResCollToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    MockERC20 reserveCollateralToken = MockERC20(address($tokens.resCollToken));

    uint256 balanceBefore = reserveCollateralToken.balanceOf(targetAddress);
    reserveCollateralToken.mint(targetAddress, amount);
    uint256 balanceAfter = reserveCollateralToken.balanceOf(targetAddress);

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint res coll token failed");
  }

  function _mintResDebtToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    vm.startPrank(address($liquidityStrategies.reserveLiquidityStrategy));
    uint256 balanceBefore = $tokens.resDebtToken.balanceOf(targetAddress);
    $tokens.resDebtToken.mint(targetAddress, amount);
    uint256 balanceAfter = $tokens.resDebtToken.balanceOf(targetAddress);
    vm.stopPrank();

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint res debt/cdp coll token failed");
  }

  function _mintCDPCollToken(address targetAddress, uint256 amount) internal {
    _mintResDebtToken(targetAddress, amount);
  }

  function _mintCDPDebtToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    vm.startPrank(address($liquity.borrowerOperations));
    uint256 balanceBefore = $tokens.cdpDebtToken.balanceOf(targetAddress);
    $tokens.cdpDebtToken.mint(targetAddress, amount);
    uint256 balanceAfter = $tokens.cdpDebtToken.balanceOf(targetAddress);
    vm.stopPrank();

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint cdp debt token failed");
  }
}
