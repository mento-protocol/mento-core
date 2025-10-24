// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { IERC20Metadata } from "bold/src/Interfaces/IBoldToken.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { IStableTokenV3 } from "contracts/interfaces/IStableTokenV3.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { TestERC20 } from "test/utils/mocks/TestERC20.sol";

contract TokenDeployer is TestStorage {
  bool private _resDebtTokenDeployed;
  bool private _cdpDebtTokenDeployed;
  bool private _resCollTokenDeployed;
  bool private _celoTokenDeployed;
  bool private _eXOFTokenDeployed;

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
    _deployCeloToken();
    _deployStableV2();
    $tokens.deployed = true;
  }

  function _deployCeloToken() private {
    address celoToken = address(new TestERC20("Celo", "cGLD"));
    vm.label(celoToken, "Celo");
    $tokens.celo = IERC20Metadata(celoToken);
    _celoTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _deployStableV2() private {
    address[] memory initialAddresses = new address[](0);
    uint256[] memory initialBalances = new uint256[](0);
    vm.startPrank($addresses.governance);
    IStableTokenV2 eXOFToken = IStableTokenV2(deployCode("StableTokenV2", abi.encode(false)));
    eXOFToken.initialize("eXOF", "eXOF", initialAddresses, initialBalances);
    vm.stopPrank();
    $tokens.exof = IStableTokenV2(address(eXOFToken));
    _eXOFTokenDeployed = true;
    _checkAllTokensDeployed();
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
    $tokens.usdm = IStableTokenV3(targetAddress);

    // Set the governance address as a minter for the Reserve Debt Token for easier testing
    vm.startPrank($addresses.governance);
    $tokens.usdm.setMinter(address($addresses.governance), true);
    vm.stopPrank();

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
    $tokens.eurm = IStableTokenV3(targetAddress);
    vm.label(targetAddress, "EUR.m");
    _cdpDebtTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _deployReserveCollToken(address targetAddress) private {
    address usdc = address(new MockERC20("Circle USD", "USDC", 6));
    _cloneContract(usdc, targetAddress, 10);

    $tokens.usdc = IERC20Metadata(targetAddress);
    vm.label(targetAddress, "USDC");
    _resCollTokenDeployed = true;
    _checkAllTokensDeployed();
  }

  function _checkAllTokensDeployed() private {
    if (
      _resDebtTokenDeployed &&
      _cdpDebtTokenDeployed &&
      _resCollTokenDeployed &&
      _celoTokenDeployed &&
      _eXOFTokenDeployed
    ) {
      $tokens.deployed = true;
    }
  }

  function _mintResCollToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    MockERC20 reserveCollateralToken = MockERC20(address($tokens.usdc));

    uint256 balanceBefore = reserveCollateralToken.balanceOf(targetAddress);
    reserveCollateralToken.mint(targetAddress, amount);
    uint256 balanceAfter = reserveCollateralToken.balanceOf(targetAddress);

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint res coll token failed");
  }

  function _mintResDebtToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    vm.startPrank(address($liquidityStrategies.reserveLiquidityStrategy));
    uint256 balanceBefore = $tokens.usdm.balanceOf(targetAddress);
    $tokens.usdm.mint(targetAddress, amount);
    uint256 balanceAfter = $tokens.usdm.balanceOf(targetAddress);
    vm.stopPrank();

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint res debt/cdp coll token failed");
  }

  function _mintCDPCollToken(address targetAddress, uint256 amount) internal {
    _mintResDebtToken(targetAddress, amount);
  }

  function _mintCDPDebtToken(address targetAddress, uint256 amount) internal {
    require($tokens.deployed, "TOKEN_DEPLOYER: tokens not deployed");

    vm.startPrank(address($liquity.borrowerOperations));
    uint256 balanceBefore = $tokens.eurm.balanceOf(targetAddress);
    $tokens.eurm.mint(targetAddress, amount);
    uint256 balanceAfter = $tokens.eurm.balanceOf(targetAddress);
    vm.stopPrank();

    require(balanceAfter == balanceBefore + amount, "TOKEN_DEPLOYER: mint cdp debt token failed");
  }

  function _cloneContract(address src, address dest, uint256 slots) internal {
    vm.etch(dest, src.code);
    for (uint256 i = 0; i < slots; ++i) {
      bytes32 slot = bytes32(i);
      vm.store(dest, slot, vm.load(src, slot));
    }
  }
}
