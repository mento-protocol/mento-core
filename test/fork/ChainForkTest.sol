// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import "./BaseForkTest.sol";

import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IStableTokenV2DeprecatedInit } from "contracts/interfaces/IStableTokenV2DEprecatedInit.sol";

contract ChainForkTest is BaseForkTest {
  using FixidityLib for FixidityLib.Fraction;

  using Utils for Utils.Context;
  using Utils for uint256;

  uint256 expectedExchangesCount;

  constructor(uint256 _chainId, uint256 _expectedExchangesCount) BaseForkTest(_chainId) {
    expectedExchangesCount = _expectedExchangesCount;
  }

  function test_biPoolManagerCanNotBeReinitialized() public {
    IBiPoolManager biPoolManager = IBiPoolManager(broker.getExchangeProviders()[0]);

    vm.expectRevert("contract already initialized");
    biPoolManager.initialize(address(broker), reserve, sortedOracles, breakerBox);
  }

  function test_brokerCanNotBeReinitialized() public {
    vm.expectRevert("contract already initialized");
    broker.initialize(new address[](0), address(reserve));
  }

  function test_sortedOraclesCanNotBeReinitialized() public {
    vm.expectRevert("contract already initialized");
    sortedOracles.initialize(1);
  }

  function test_reserveCanNotBeReinitialized() public {
    vm.expectRevert("contract already initialized");
    reserve.initialize(
      address(10),
      0,
      0,
      0,
      0,
      new bytes32[](0),
      new uint256[](0),
      0,
      0,
      new address[](0),
      new uint256[](0)
    );
  }

  function test_testsAreConfigured() public view {
    assertEq(expectedExchangesCount, exchanges.length);
  }

  function test_stableTokensCanNotBeReinitialized() public {
    IStableTokenV2DeprecatedInit stableToken = IStableTokenV2DeprecatedInit(
      registry.getAddressForStringOrDie("StableToken")
    );
    IStableTokenV2DeprecatedInit stableTokenEUR = IStableTokenV2DeprecatedInit(
      registry.getAddressForStringOrDie("StableTokenEUR")
    );
    IStableTokenV2DeprecatedInit stableTokenBRL = IStableTokenV2DeprecatedInit(
      registry.getAddressForStringOrDie("StableTokenBRL")
    );
    IStableTokenV2DeprecatedInit stableTokenXOF = IStableTokenV2DeprecatedInit(
      registry.getAddressForStringOrDie("StableTokenXOF")
    );
    IStableTokenV2DeprecatedInit stableTokenKES = IStableTokenV2DeprecatedInit(
      registry.getAddressForStringOrDie("StableTokenKES")
    );

    vm.expectRevert("Initializable: contract is already initialized");
    stableToken.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");

    vm.expectRevert("Initializable: contract is already initialized");
    stableTokenEUR.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");

    vm.expectRevert("Initializable: contract is already initialized");
    stableTokenBRL.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");

    vm.expectRevert("Initializable: contract is already initialized");
    stableTokenXOF.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");

    vm.expectRevert("Initializable: contract is already initialized");
    stableTokenKES.initialize("", "", 8, address(10), 0, 0, new address[](0), new uint256[](0), "");
  }
}
