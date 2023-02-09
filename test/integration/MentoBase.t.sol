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

  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);
  ExchangeWithProvider[] public exchanges;

  Broker public broker;
  SortedOracles public sortedOracles;

  struct ExchangeWithProvider {
    address exchangeProvider;
    IExchangeProvider.Exchange exchange;
  }

  address trader0;

  function setUp() public {
    broker = Broker(registry.getAddressForStringOrDie("Broker"));
    sortedOracles = SortedOracles(registry.getAddressForStringOrDie("SortedOracles"));
    trader0 = actor("trader0");
    changePrank(trader0);

    vm.label(address(broker), "Broker");

    address[] memory exchangeProviders = broker.getExchangeProviders();
    for (uint i = 0; i < exchangeProviders.length; i++) {
      IExchangeProvider.Exchange[] memory _exchanges = IExchangeProvider(exchangeProviders[i]).getExchanges();
      for (uint j = 0; j < _exchanges.length; j++) {
        exchanges.push(ExchangeWithProvider(exchangeProviders[i], _exchanges[j]));
      }
    }

    // print all exchanges
    for (uint i = 0; i < exchanges.length; i++) {
      console.log(i, exchanges[i].exchangeProvider, exchanges[i].exchange.assets[0], exchanges[i].exchange.assets[1]);
    }
  }

  function test_swaps_happen_in_both_directions() public {
    for (uint i = 0; i < exchanges.length; i++) {
      _test_swaps_happen_in_both_directions(exchanges[i]);
    }
  }

  function _test_swaps_happen_in_both_directions(ExchangeWithProvider memory exchangeWithProvider) internal {
    address exchangeProvider = exchangeWithProvider.exchangeProvider;
    IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;
    (uint256 numerator, uint256 denominator) = getReferenceRate(exchangeProvider, exchange.exchangeId);
    FixidityLib.Fraction memory rate = FixidityLib.newFixedFraction(numerator, denominator);

    // asset0 -> asset1
    uint256 asset0Amount = 1000 * 1e18;
    mint(exchange.assets[0], trader0, asset0Amount);
    IERC20Metadata(exchange.assets[0]).approve(address(broker), asset0Amount);
    uint256 minAmountOut = broker.getAmountOut(exchangeProvider, exchange.exchangeId, exchange.assets[0], exchange.assets[1], asset0Amount) - 1e19;
    uint256 amountOut = broker.swapIn(exchangeProvider, exchange.exchangeId, exchange.assets[0], exchange.assets[1], asset0Amount, minAmountOut);

    uint256 expectedAmountOut = FixidityLib.newFixed(asset0Amount).divide(rate).unwrap() / FixidityLib.fixed1().unwrap();
    assertApproxEqAbs(
      amountOut, 
      expectedAmountOut, 
      FixidityLib.newFixedFraction(10, 100).multiply(FixidityLib.newFixed(expectedAmountOut)).unwrap() / FixidityLib.fixed1().unwrap()
    );

    // asset1 -> asset0
    uint256 asset1Amount = 1000 * 1e18;

    mint(exchange.assets[1], trader0, 1000);
    IERC20Metadata(exchange.assets[1]).approve(address(broker), 1000);
    minAmountOut = broker.getAmountOut(exchangeProvider, exchange.exchangeId, exchange.assets[1], exchange.assets[0], asset1Amount) - 1e19;
    amountOut = broker.swapIn(exchangeProvider, exchange.exchangeId, exchange.assets[1], exchange.assets[0], asset1Amount, minAmountOut);

    expectedAmountOut = FixidityLib.newFixed(asset1Amount).divide(rate).unwrap() / FixidityLib.fixed1().unwrap();
    assertApproxEqAbs(
      amountOut, 
      expectedAmountOut, 
      FixidityLib.newFixedFraction(10, 100).multiply(FixidityLib.newFixed(expectedAmountOut)).unwrap() / FixidityLib.fixed1().unwrap()
    );
  }

  function getReferenceRate(address exchangeProvider, bytes32 exchangeId) internal returns (uint256, uint256) {
    // TODO: extend this when we have multiple exchange providers, for now assume it's an BiPoolManager
    BiPoolManager biPoolManager = BiPoolManager(exchangeProvider);
    BiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(exchangeId);
    uint256 rateNumerator;
    uint256 rateDenominator;
    (rateNumerator, rateDenominator) = sortedOracles.medianRate(pool.config.referenceRateFeedID);
    require(rateDenominator > 0, "exchange rate denominator must be greater than 0");
    return (rateNumerator, rateDenominator);
  }
}

