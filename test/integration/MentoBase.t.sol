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
import { TradingLimits } from "contracts/common/TradingLimits.sol";

/**
 * @title IBrokerWithTradingLimits
 * @notice Interface for Broker with trading limits
 * @dev This is used to access the internal trading limits state and 
 * config as structs as opposed to tuples.
 */
interface IBrokerWithTradingLimits {
  function tradingLimitsState(bytes32 id) external view returns (TradingLimits.State memory);
  function tradingLimitsConfig(bytes32 id) external view returns (TradingLimits.Config memory);
}

/** 
 * @title MentoBaseForkTest
 * @notice Fork tests for Mento!
 * This test suite tests invariantes on a fork of a live Mento environemnts.
 * The philosophy is to test in accordance with how the target fork is configured,
 * therfore it doesn't make assumptions about the systems, nor tries to configure
 * the system to test specific scenarios.
 * However, it should be exausitve in testing invariants across all tradable pairs
 * in the system, therfore each test should.
 */
contract MentoBaseForkTest is Test, TokenHelpers {
  using FixidityLib for FixidityLib.Fraction;
  using TradingLimits for TradingLimits.State;
  using TradingLimits for TradingLimits.Config;

  struct ExchangeWithProvider {
    address exchangeProvider;
    IExchangeProvider.Exchange exchange;
  }

  address public constant REGISTRY_ADDRESS = 0x000000000000000000000000000000000000ce10;
  IRegistry public registry = IRegistry(REGISTRY_ADDRESS);

  FixidityLib.Fraction pc10 = FixidityLib.newFixedFraction(10, 100);
  uint256 fixed1 = FixidityLib.fixed1().unwrap();

  Broker public broker;
  IBrokerWithTradingLimits public brokerForLimits;

  SortedOracles public sortedOracles;
  address governance;

  address trader0;

  ExchangeWithProvider[] public exchanges;
  mapping(address => mapping(bytes32 => ExchangeWithProvider)) public exchangeMap;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  function setUp() public {
    broker = Broker(registry.getAddressForStringOrDie("Broker"));
    brokerForLimits = IBrokerWithTradingLimits(address(broker));
    sortedOracles = SortedOracles(registry.getAddressForStringOrDie("SortedOracles"));
    governance = registry.getAddressForStringOrDie("Governance");
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

    // XXX: Temporarily add trading limits to broker
    // These are not the real trading limits, but they are good enough for testing.
    changePrank(governance);
    for (uint256 i = 0; i < exchanges.length; i++) {
      IExchangeProvider.Exchange memory exchange = exchanges[i].exchange;
      TradingLimits.Config memory config = TradingLimits.Config(
        60 * 5, // 5min
        60 * 60 * 24, // 1day
        1_000,
        10_000,
        100_000,
        L0 | L1 | LG
      );
      broker.configureTradingLimit(exchange.exchangeId, exchange.assets[0], config);
      // broker.configureTradingLimit(exchange.exchangeId, exchange.assets[1], config);
    }
    changePrank(trader0);
  }

  function test_swapsHappenInBothDirections() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset0 -> asset1
      assert_swap(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        toSubunits(1000, exchange.assets[0])
      );
      // asset1 -> asset0
      assert_swap(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        toSubunits(1000, exchange.assets[1])
      );
    }
  }

  function test_tradingLimitsAreEnforced_0to1_L0() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset0 -> asset1
      assert_swapOverLimitFails_L0(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        exchange.assets[0]
      );
      assert_swapOverLimitFails_L0(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        exchange.assets[1]
      ); 
    }
  }

  function test_tradingLimitsAreEnforced_0to1_L1() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset0 -> asset1
      assert_swapOverLimitFails_L1(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        exchange.assets[0]
      );
      assert_swapOverLimitFails_L1(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        exchange.assets[1]
      ); 
    }
  }

  function test_tradingLimitsAreEnforced_0to1_LG() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset0 -> asset1
      assert_swapOverLimitFails_LG(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        exchange.assets[0]
      );
      assert_swapOverLimitFails_LG(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[0],
        exchange.assets[1],
        exchange.assets[1]
      ); 
    }
  }

  function test_tradingLimitsAreEnforced_1to0_L0() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset1 -> asset0 
      assert_swapOverLimitFails_L0(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        exchange.assets[0]
      );
      assert_swapOverLimitFails_L0(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        exchange.assets[1]
      );
    }
  }

  function test_tradingLimitsAreEnforced_1to0_L1() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset1 -> asset0 
      assert_swapOverLimitFails_L1(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        exchange.assets[0]
      );
      assert_swapOverLimitFails_L1(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        exchange.assets[1]
      );
    }
  }

  function test_tradingLimitsAreEnforced_1to0_LG() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      // asset1 -> asset0 
      assert_swapOverLimitFails_LG(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        exchange.assets[0]
      );
      assert_swapOverLimitFails_LG(
        exchangeWithProvider.exchangeProvider,
        exchange.exchangeId,
        exchange.assets[1],
        exchange.assets[0],
        exchange.assets[1]
      );
    }
  }

  function test_tradingLimitsAreConfigured() public {
    for (uint256 i = 0; i < exchanges.length; i++) {
      ExchangeWithProvider memory exchangeWithProvider = exchanges[i];
      IExchangeProvider.Exchange memory exchange = exchangeWithProvider.exchange;

      bytes32 asset0Bytes32 = bytes32(uint256(uint160(exchange.assets[0])));
      bytes32 limitIdForAsset0 = exchange.exchangeId ^ asset0Bytes32;
      bytes32 asset1Bytes32 = bytes32(uint256(uint160(exchange.assets[1])));
      bytes32 limitIdForAsset1 = exchange.exchangeId ^ asset1Bytes32;

      require(isLimitConfigured(limitIdForAsset0) || isLimitConfigured(limitIdForAsset1), "Limit not configured");
    }
  }

  function assert_swap(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    uint256 sellAmount
  ) internal {
    FixidityLib.Fraction memory rate = getReferenceRateFraction(exchangeProvider, exchangeId, from);
    uint256 amountOut = doSwap(exchangeProvider, exchangeId, from, to, sellAmount);
    uint256 expectedAmountOut = FixidityLib.newFixed(sellAmount).divide(rate).unwrap() / fixed1;
    assertApproxEqAbs(
      amountOut,
      expectedAmountOut,
      pc10.multiply(FixidityLib.newFixed(expectedAmountOut)).unwrap() / fixed1
    );
  }

  function assert_swapReverts(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    uint256 sellAmount,
    string memory revertReason
  ) internal {
    FixidityLib.Fraction memory rate = getReferenceRateFraction(exchangeProvider, exchangeId, from);
    mint(from, trader0, sellAmount);
    IERC20Metadata(from).approve(address(broker), sellAmount);

    uint256 minAmountOut = broker.getAmountOut(exchangeProvider, exchangeId, from, to, sellAmount); // slippage
    vm.expectRevert(bytes(revertReason));
    uint256 amountOut = broker.swapIn(exchangeProvider, exchangeId, from, to, sellAmount, minAmountOut);
  }

  function assert_swapOverLimitFails_L0(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    address assetToVerifyLimit
  ) internal {
    bytes32 assetToVerifyLimitBytes32 = bytes32(uint256(uint160(assetToVerifyLimit)));
    TradingLimits.Config memory limitConfig = brokerForLimits.tradingLimitsConfig(exchangeId ^ assetToVerifyLimitBytes32);
    TradingLimits.State memory limitState = brokerForLimits.tradingLimitsState(exchangeId ^ assetToVerifyLimitBytes32);

    if (limitConfig.flags & L0 > 0) {
      assert_swapOverLimitFailsForLimit(
        exchangeProvider,
        exchangeId,
        from,
        to,
        assetToVerifyLimit,
        limitConfig.limit0,
        limitState.netflow0
      );
    }
  }

  function assert_swapOverLimitFails_L1(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    address assetToVerifyLimit
  ) internal {
    bytes32 assetToVerifyLimitBytes32 = bytes32(uint256(uint160(assetToVerifyLimit)));
    TradingLimits.Config memory limitConfig = brokerForLimits.tradingLimitsConfig(exchangeId ^ assetToVerifyLimitBytes32);
    TradingLimits.State memory limitState = brokerForLimits.tradingLimitsState(exchangeId ^ assetToVerifyLimitBytes32);

    if (limitConfig.flags & L1 > 0) {
      TradingLimits.State memory limitState = brokerForLimits.tradingLimitsState(exchangeId ^ assetToVerifyLimitBytes32);
      assert_swapOverLimitFailsForLimitInIncrements(
        exchangeProvider,
        exchangeId,
        from,
        to,
        assetToVerifyLimit,
        limitConfig.limit1,
        limitState.netflow1,
        limitConfig.limit0 - 1,
        limitConfig.timestep0,
        "L1 Exceeded"
      );
    }
  }

  function assert_swapOverLimitFails_LG(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    address assetToVerifyLimit
  ) internal {
    bytes32 assetToVerifyLimitBytes32 = bytes32(uint256(uint160(assetToVerifyLimit)));
    TradingLimits.Config memory limitConfig = brokerForLimits.tradingLimitsConfig(exchangeId ^ assetToVerifyLimitBytes32);
    TradingLimits.State memory limitState = brokerForLimits.tradingLimitsState(exchangeId ^ assetToVerifyLimitBytes32);

    if (limitConfig.flags & LG > 0) {
      if (limitConfig.flags & L0 == 0 && limitConfig.flags & L1 == 0) {
        assert_swapOverLimitFailsForLimit(
          exchangeProvider,
          exchangeId,
          from,
          to,
          assetToVerifyLimit,
          limitConfig.limitGlobal,
          limitState.netflowGlobal
        );
      } else {
        uint32 limitResetInterval = limitConfig.timestep0;
        if (limitConfig.flags & L1 > 0) {
          limitResetInterval = limitConfig.timestep1;
        }
        assert_swapOverLimitFailsForLimitInIncrements(
          exchangeProvider,
          exchangeId,
          from,
          to,
          assetToVerifyLimit,
          limitConfig.limitGlobal,
          limitState.netflowGlobal,
          limitConfig.limit0 - 1,
          limitResetInterval,
          "LG Exceeded"
        );
      }
    }
  }

  function assert_swapOverLimitFailsForLimitInIncrements(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    address assetToVerifyLimit,
    int48 limit,
    int48 netflow,
    int48 maxAmountPerSwap,
    uint32 limitResetInterval,
    string memory revertReason
  ) internal {
    if (from == assetToVerifyLimit) {
      assert_swapOverLimitFailsForLimitInIncrements_positive(
        exchangeProvider,
        exchangeId,
        from,
        to,
        limit,
        netflow,
        maxAmountPerSwap,
        limitResetInterval,
        revertReason
      );
    } else {
      assert_swapOverLimitFailsForLimitInIncrements_negative(
        exchangeProvider,
        exchangeId,
        from,
        to,
        limit,
        netflow,
        maxAmountPerSwap,
        limitResetInterval,
        revertReason
      );
    }
  }

  function assert_swapOverLimitFailsForLimitInIncrements_positive(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    int48 limit,
    int48 netflow,
    int48 maxAmountPerSwap,
    uint32 limitResetInterval,
    string memory revertReason
  ) internal {
    // L[from] -> to, `from` flows into the reserve, so limit tested on positive end
    require(limit - netflow >= 0, "otherwise the limit has been passed");
    uint256 inflowRequiredUnits = uint256(limit - netflow) + 1;
    console.logInt(limit);
    console.logInt(netflow);
    console.log("Inflow required: ", inflowRequiredUnits);

    int256 swapped = netflow;
    while (swapped + maxAmountPerSwap < limit) {
      console.log("blocktime before:", block.timestamp);
      skip(limitResetInterval + 1);
      console.log("blocktime after:", block.timestamp);

      doSwap(exchangeProvider, exchangeId, from, to, toSubunits(uint256(maxAmountPerSwap), from));
      swapped += maxAmountPerSwap;
      console.log("swapped: ");
      console.logInt(swapped);
    }
    console.log("blocktime before:", block.timestamp);
    skip(limitResetInterval + 1);
    console.log("blocktime after:", block.timestamp);
    assert_swapReverts(
      exchangeProvider,
      exchangeId,
      from,
      to,
      toSubunits(uint256(maxAmountPerSwap), from),
      revertReason
    );
  }

  function assert_swapOverLimitFailsForLimitInIncrements_negative(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    int48 limit,
    int48 netflow,
    int48 maxAmountPerSwap,
    uint32 limitResetInterval,
    string memory revertReason
  ) internal {
    // from -> L[to], `to` flows out of the reserve, so limit tested on negative end
    // TODO: Implement this the right way
    require(limit + netflow >= 0, "otherwise the limit has been passed");
    // console.log(outflowRequiredUnits);
    // uint256 inflowRequiredUnits = FixidityLib.newFixed(outflowRequiredUnits).multiply(rate).unwrap() / fixed1;
    // console.logInt(limit);
    // console.logInt(netflow);
    // console.log("Outflow required: ", outflowRequiredUnits);
    // console.log("Inflow required: ", inflowRequiredUnits);
    // assert_swapReverts(exchangeProvider, exchangeId, from, to, inflowRequiredUnits, "L0 Exceeded");

    console.logInt(limit);
    console.logInt(netflow);

    int256 swapped = netflow;
    while (swapped - maxAmountPerSwap > -1 * limit) {
      console.log("blocktime before:", block.timestamp);
      skip(limitResetInterval + 1);
      console.log("blocktime after:", block.timestamp);
      uint256 amountIn = 
        broker.getAmountIn(
          exchangeProvider,
          exchangeId,
          from,
          to,
          toSubunits(uint256(maxAmountPerSwap), to)
        );
      doSwap(
        exchangeProvider, 
        exchangeId, 
        from, 
        to, 
        amountIn
      );
      swapped -= maxAmountPerSwap;
      console.log("swapped: ");
      console.logInt(swapped);
    }
    console.log("blocktime before:", block.timestamp);
    skip(limitResetInterval + 1);
    console.log("blocktime after:", block.timestamp);
    uint256 amountIn = 
      broker.getAmountIn(
        exchangeProvider,
        exchangeId,
        from,
        to,
        toSubunits(uint256(maxAmountPerSwap), to)
      );

    assert_swapReverts(
      exchangeProvider,
      exchangeId,
      from,
      to,
      amountIn,
      revertReason
    );
  }

  function assert_swapOverLimitFailsForLimit(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    address assetToVerifyLimit,
    int48 limit,
    int48 netflow
  ) internal {
    if (from == assetToVerifyLimit) {
      // L[from] -> to, `from` flows into the reserve, so limit tested on positive end
      require(limit - netflow >= 0, "otherwise the limit has been passed");
      uint256 inflowRequiredUnits = uint256(limit - netflow) + 2;
      assert_swapReverts(exchangeProvider, exchangeId, from, to, toSubunits(inflowRequiredUnits, from), "L0 Exceeded");
    } else {
      // from -> L[to], `to` flows out of the reserve, so limit tested on negative end
      require(limit + netflow >= 0, "otherwise the limit has been passed");
      uint256 outflowRequiredUnits = uint256(limit + netflow) + 2; /// add a little bit more to ensure we get over the limit with rounding precision
      console.logInt(limit);
      console.logInt(netflow);
      console.log("Outflow required: ", outflowRequiredUnits);
      uint256 inflowRequired = broker.getAmountIn(
        exchangeProvider,
        exchangeId,
        from,
        to,
        toSubunits(outflowRequiredUnits, to)
      );
      assert_swapReverts(exchangeProvider, exchangeId, from, to, inflowRequired, "L0 Exceeded");
    }
  }

  function doSwap(
    address exchangeProvider,
    bytes32 exchangeId,
    address from,
    address to,
    uint256 sellAmount
  ) internal returns (uint256) {
    mint(from, trader0, sellAmount);
    IERC20Metadata(from).approve(address(broker), sellAmount);

    uint256 tokenBase = 10**uint256(IERC20Metadata(from).decimals());
    uint256 minAmountOut = broker.getAmountOut(exchangeProvider, exchangeId, from, to, sellAmount) - (10 * tokenBase); // slippage
    return broker.swapIn(exchangeProvider, exchangeId, from, to, sellAmount, minAmountOut);
  }


  function isLimitConfigured(bytes32 limitId) internal returns (bool) {
    TradingLimits.Config memory limitConfig = brokerForLimits.tradingLimitsConfig(limitId);
    return limitConfig.flags > uint8(0);
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

  function toSubunits(uint256 units, address token) internal returns (uint256) {
    uint256 tokenBase = 10**uint256(IERC20Metadata(token).decimals());
    return units * tokenBase;
  }
}
