// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import "./BaseForkTest.sol";

import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IStableTokenV2DeprecatedInit } from "contracts/interfaces/IStableTokenV2DeprecatedInit.sol";

abstract contract ChainForkTest is BaseForkTest {
  using FixidityLib for FixidityLib.Fraction;

  uint256 expectedExchangeProvidersCount;
  uint256[] expectedExchangesCount;

  constructor(
    uint256 _chainId,
    uint256 _expectedExchangesProvidersCount,
    uint256[] memory _expectedExchangesCount
  ) BaseForkTest(_chainId) {
    expectedExchangesCount = _expectedExchangesCount;
    expectedExchangeProvidersCount = _expectedExchangesProvidersCount;
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

  /**
   * @dev If this fails it means we have added new exchanges
   * and haven't updated the fork test configuration which
   * can be found in ForkTests.t.sol.
   */
  function test_exchangeProvidersAndExchangesCount() public view {
    address[] memory exchangeProviders = broker.getExchangeProviders();
    assertEq(expectedExchangeProvidersCount, exchangeProviders.length);
    for (uint i = 0; i < exchangeProviders.length; i++) {
      address exchangeProvider = exchangeProviders[i];
      IBiPoolManager biPoolManager = IBiPoolManager(exchangeProvider);
      IExchangeProvider.Exchange[] memory exchanges = biPoolManager.getExchanges();
      assertEq(expectedExchangesCount[i], exchanges.length);
    }
  }

  function test_numberCollateralAssetsCount() public {
    address collateral;
    for (uint i = 0; i < COLLATERAL_ASSETS_COUNT; i++) {
      collateral = reserve.collateralAssets(i);
    }
    /**
     * @dev If this fails it means we have added a new collateral
     * so we need to update the COLLATERAL_ASSETS constant.
     * This is because we don't have an easy way to determine
     * the number of collateral assets in the system.
     */
    vm.expectRevert();
    reserve.collateralAssets(COLLATERAL_ASSETS_COUNT);
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

  function test_rateFeedDependenciesCountIsCorrect() public {
    address[] memory rateFeedIds = breakerBox.getRateFeeds();
    for (uint i = 0; i < rateFeedIds.length; i++) {
      address rateFeedId = rateFeedIds[i];
      uint8 count = rateFeedDependenciesCount[rateFeedId];

      vm.expectRevert();
      breakerBox.rateFeedDependencies(rateFeedId, count); // end of array

      for (uint j = 0; j < count; j++) {
        (bool ok, ) = address(breakerBox).staticcall(
          abi.encodeWithSelector(breakerBox.rateFeedDependencies.selector, rateFeedId, j)
        );
        if (!ok) {
          console.log("Dependency missing for rateFeedId=%s, expectedCount=%d, missingIndex=%d", rateFeedId, count, j);
          console.log(
            "If the configuration has changed, update the rateFeedDependenciesCount mapping in BaseForfTest.sol"
          );
        }
        require(ok, "rateFeedDependenciesCount out of sync");
      }
    }
  }
}
