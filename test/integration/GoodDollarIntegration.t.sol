// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { BaseTest } from "../utils/BaseTest.t.sol";
import { console2 as console } from "celo-foundry/Test.sol";

import { IGoodDollarExchangeProvider } from "contracts/goodDollar/interfaces/IGoodDollarExchangeProvider.sol";
import { IGoodDollarExpansionController } from "contracts/goodDollar/interfaces/IGoodDollarExpansionController.sol";
import { IBancorExchangeProvider } from "contracts/goodDollar/interfaces/IBancorExchangeProvider.sol";
import { IStableTokenV2 } from "contracts/interfaces/IStableTokenV2.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";

import { BrokerV2 } from "contracts/swap/BrokerV2.sol";
import { Reserve } from "contracts/swap/Reserve.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";

contract GoodDollarIntegrationTest is BaseTest {
  using FixidityLib for FixidityLib.Fraction;
  address public trader;
  address public interestCollector;

  address public avatar;
  address public sortedOracles;
  address public distributionHelper;

  BrokerV2 public broker;
  Reserve public reserve;
  IStableTokenV2 public reserveToken;
  IStableTokenV2 public gdToken;

  IGoodDollarExchangeProvider public exchangeProvider;
  IGoodDollarExpansionController public expansionController;

  IBancorExchangeProvider.PoolExchange public poolExchange1;
  bytes32 public exchangeId;

  function setUp() public {
    reserve = new Reserve(true);
    gdToken = IStableTokenV2(factory.createContract("StableTokenV2", abi.encode(false)));
    reserveToken = IStableTokenV2(factory.createContract("StableTokenV2", abi.encode(false)));
    broker = new BrokerV2(true);
    exchangeProvider = IGoodDollarExchangeProvider(
      factory.createContract("GoodDollarExchangeProvider", abi.encode(false))
    );
    expansionController = IGoodDollarExpansionController(
      factory.createContract("GoodDollarExpansionController", abi.encode(false))
    );
    sortedOracles = actor("sortedOracles");
    avatar = actor("avatar");
    distributionHelper = actor("distributionHelper");
    trader = actor("trader");

    configureReserve();
    configureTokens();
    configureBroker();
    configureExchangeProvider();
    configureExpansionController();
  }

  function configureReserve() public {
    bytes32[] memory initialAssetAllocationSymbols = new bytes32[](2);
    initialAssetAllocationSymbols[0] = bytes32("cGLD");
    initialAssetAllocationSymbols[1] = bytes32("cUSD");

    uint256[] memory initialAssetAllocationWeights = new uint256[](2);
    initialAssetAllocationWeights[0] = FixidityLib.newFixedFraction(1, 2).unwrap();
    initialAssetAllocationWeights[1] = FixidityLib.newFixedFraction(1, 2).unwrap();

    uint256 tobinTax = FixidityLib.newFixedFraction(5, 1000).unwrap();
    uint256 tobinTaxReserveRatio = FixidityLib.newFixedFraction(2, 1).unwrap();

    address[] memory collateralAssets = new address[](1);
    collateralAssets[0] = address(reserveToken);

    uint256[] memory collateralAssetDailySpendingRatios = new uint256[](1);
    collateralAssetDailySpendingRatios[0] = 1e24;

    reserve.initialize(
      actor("registry"),
      600, // deprecated
      1000000000000000000000000,
      0,
      0,
      initialAssetAllocationSymbols,
      initialAssetAllocationWeights,
      tobinTax,
      tobinTaxReserveRatio,
      collateralAssets,
      collateralAssetDailySpendingRatios
    );

    reserve.addToken(address(gdToken));
    reserve.addExchangeSpender(address(broker));
  }

  function configureTokens() public {
    reserveToken.initialize("Celo Dollar", "cUSD", 0, address(0), 0, 0, new address[](0), new uint256[](0), "");
    reserveToken.initializeV2(address(broker), address(0), address(0));

    gdToken.initialize("GoodDollar", "G$", 0, address(0), 0, 0, new address[](0), new uint256[](0), "");
    gdToken.initializeV2(address(broker), address(0), address(0));

    deal(address(reserveToken), address(reserve), 60_000 * 1e18);
  }

  function configureBroker() public {
    address[] memory exchangeProviders = new address[](1);
    address[] memory reserves = new address[](1);
    exchangeProviders[0] = address(exchangeProvider);
    reserves[0] = address(reserve);
    broker.initialize(exchangeProviders, reserves);
  }

  function configureExchangeProvider() public {
    exchangeProvider.initialize(address(broker), address(reserve), sortedOracles, address(expansionController), avatar);
    vm.mockCall(sortedOracles, abi.encodeWithSelector(ISortedOracles(sortedOracles).numRates.selector), abi.encode(10));

    poolExchange1 = IBancorExchangeProvider.PoolExchange({
      reserveAsset: address(reserveToken),
      tokenAddress: address(gdToken),
      tokenSupply: 300_000 * 1e18,
      reserveBalance: 60_000 * 1e18,
      reserveRatio: 200000,
      exitConribution: 10000
    });

    exchangeId = exchangeProvider.createExchange(poolExchange1, address(reserveToken));
  }

  function configureExpansionController() public {
    expansionController.initialize(address(exchangeProvider), distributionHelper, address(reserve), avatar);
  }

  function test_SwapIn_reserveTokenToGDollar() public {
    uint256 amountIn = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountOut = broker.getAmountOut(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountIn
    );

    deal(address(reserveToken), trader, amountIn);

    vm.startPrank(trader);
    reserveToken.approve(address(broker), amountIn);
    broker.swapIn(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountIn,
      expectedAmountOut
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(expectedAmountOut, gdToken.balanceOf(trader));
    assertEq(reserveBalanceBefore + amountIn, reserveBalanceAfter);
    assertTrue(priceBefore < priceAfter);
  }

  function test_SwapIn_gDollarToReserveToken() public {
    uint256 amountIn = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountOut = broker.getAmountOut(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountIn
    );

    deal(address(gdToken), trader, amountIn);

    vm.startPrank(trader);
    gdToken.approve(address(broker), amountIn);
    broker.swapIn(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountIn,
      expectedAmountOut
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(expectedAmountOut, reserveToken.balanceOf(trader));
    assertEq(reserveBalanceBefore - expectedAmountOut, reserveBalanceAfter);
    assertTrue(priceAfter < priceBefore);
  }

  function test_SwapOut_reserveTokenToGDollar() public {
    uint256 amountOut = 1000 * 1e18;
    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountIn = broker.getAmountIn(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountOut
    );

    deal(address(reserveToken), trader, expectedAmountIn);

    vm.startPrank(trader);
    reserveToken.approve(address(broker), expectedAmountIn);
    broker.swapOut(
      address(exchangeProvider),
      exchangeId,
      address(reserveToken),
      address(gdToken),
      amountOut,
      expectedAmountIn
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(amountOut, gdToken.balanceOf(trader));
    assertEq(reserveBalanceBefore + expectedAmountIn, reserveBalanceAfter);
    assertTrue(priceBefore < priceAfter);
  }

  function test_SwapOut_gDollarToReserveToken() public {
    uint256 amountOut = 1000 * 1e18;

    uint256 reserveBalanceBefore = reserveToken.balanceOf(address(reserve));
    uint256 priceBefore = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 expectedAmountIn = broker.getAmountIn(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountOut
    );

    deal(address(gdToken), trader, expectedAmountIn);

    vm.startPrank(trader);
    gdToken.approve(address(broker), expectedAmountIn);
    broker.swapOut(
      address(exchangeProvider),
      exchangeId,
      address(gdToken),
      address(reserveToken),
      amountOut,
      expectedAmountIn
    );
    uint256 priceAfter = IBancorExchangeProvider(address(exchangeProvider)).currentPrice(exchangeId);
    uint256 reserveBalanceAfter = reserveToken.balanceOf(address(reserve));

    assertEq(amountOut, reserveToken.balanceOf(trader));
    assertEq(reserveBalanceBefore - amountOut, reserveBalanceAfter);
    assertTrue(priceAfter < priceBefore);
  }
}
