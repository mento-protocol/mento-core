// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test } from "celo-foundry/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { TokenHelpers } from "test/utils/TokenHelpers.t.sol";

import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IRegistry } from "contracts/common/interfaces/IRegistry.sol";
import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

import { Broker } from "contracts/Broker.sol";
import { SortedOracles } from "contracts/SortedOracles.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";

contract MentoBaseForkTest is Test, TokenHelpers {
  using FixidityLib for FixidityLib.Fraction;

  struct ExchangeWithProvider {
    address exchangeProvider;
    IExchangeProvider.Exchange exchange;
  }

  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);
  FixidityLib.Fraction pc10 = FixidityLib.newFixedFraction(10, 100);

  Broker public broker;
  SortedOracles public sortedOracles;

  address trader0;

  ExchangeWithProvider[] public exchanges;
  mapping(address => mapping(bytes32 => ExchangeWithProvider)) public exchangeMap;

  function setUp() public {
    broker = Broker(registry.getAddressForStringOrDie("Broker"));
    sortedOracles = SortedOracles(registry.getAddressForStringOrDie("SortedOracles"));
    trader0 = actor("trader0");
    changePrank(trader0);

    vm.label(address(broker), "Broker");

    address[] memory exchangeProviders = broker.getExchangeProviders();
    for (uint256 i = 0; i < exchangeProviders.length; i++) {
      IExchangeProvider.Exchange[] memory _exchanges = IExchangeProvider(exchangeProviders[i]).getExchanges();
      for (uint256 j = 0; j < _exchanges.length; j++) {
        exchanges.push(ExchangeWithProvider(exchangeProviders[i], _exchanges[j]));
        exchangeMap[exchangeProviders[i]][_exchanges[j].exchangeId] = ExchangeWithProvider(
          exchangeProviders[i],
          _exchanges[j]
        );
      }
    }

    for (uint256 i = 0; i < exchanges.length; i++) {
      console.log(i, exchanges[i].exchangeProvider, exchanges[i].exchange.assets[0], exchanges[i].exchange.assets[1]);
    }
  }

  function test_swaps_happen_in_both_directions() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset0 -> asset1
      assert_swap(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        1000
      );
      // asset1 -> asset0
      assert_swap(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        1000
      );
    }
  }

  function assert_swap(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    uint256 sellAmountUnits
  ) internal {
    (uint256 numerator, uint256 denominator) = getReferenceRate(exchangeProvider, exchangeId);
    FixidityLib.Fraction memory rate = getReferenceRateFraction(exchangeProvider, exchangeId, from);
    uint256 tokenBase = 10**uint256(IERC20Metadata(from).decimals());

    uint256 sellAmount = sellAmountUnits * tokenBase;
    mint(from, trader0, sellAmount);
    IERC20Metadata(from).approve(address(broker), sellAmount);

    uint256 minAmountOut = broker.getAmountOut(exchangeProvider, exchangeId, from, to, sellAmount) - (10 * tokenBase); // slippage
    uint256 amountOut = broker.swapIn(exchangeProvider, exchangeId, from, to, sellAmount, minAmountOut);

    uint256 expectedAmountOut = FixidityLib.newFixed(sellAmount).divide(rate).unwrap() / FixidityLib.fixed1().unwrap();
    assertApproxEqAbs(
      amountOut,
      expectedAmountOut,
      pc10.multiply(FixidityLib.newFixed(expectedAmountOut)).unwrap() / FixidityLib.fixed1().unwrap()
    );
  }

  function getReferenceRateFraction(
    address exchangeProvider,
    bytes32 exchangeId,
    address baseAsset
  ) internal returns (FixidityLib.Fraction memory) {
    (uint256 numerator, uint256 denominator) = getReferenceRate(exchangeProvider, exchangeId);
    address asset0 = exchangeMap[exchangeProvider][exchangeId].exchange.assets[0];
    if (baseAsset == asset0) {
      return FixidityLib.newFixedFraction(numerator, denominator);
    }
    return FixidityLib.newFixedFraction(denominator, numerator);
  }

  function getReferenceRate(address exchangeProvider, bytes32 exchangeId) internal returns (uint256, uint256) {
    // TODO: extend this when we have multiple exchange providers, for now assume it's a BiPoolManager
    BiPoolManager biPoolManager = BiPoolManager(exchangeProvider);
    BiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(exchangeId);
    uint256 rateNumerator;
    uint256 rateDenominator;
    (rateNumerator, rateDenominator) = sortedOracles.medianRate(pool.config.referenceRateFeedID);
    require(rateDenominator > 0, "exchange rate denominator must be greater than 0");
    return (rateNumerator, rateDenominator);
  }
}
