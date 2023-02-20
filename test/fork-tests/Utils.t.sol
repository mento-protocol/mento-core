// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { BaseForkTest } from "./BaseForkTest.t.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";

import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";

import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { TradingLimits } from "contracts/common/TradingLimits.sol";

import { Broker } from "contracts/Broker.sol";
import { BreakerBox } from "contracts/BreakerBox.sol";
import { BiPoolManager } from "contracts/BiPoolManager.sol";
import { SortedOracles } from "contracts/SortedOracles.sol";
import { MedianDeltaBreaker } from "contracts/MedianDeltaBreaker.sol";
import { ValueDeltaBreaker } from "contracts/ValueDeltaBreaker.sol";
import { WithThreshold } from "contracts/common/breakers/WithThreshold.sol";

/**
 * @title IBrokerWithCasts
 * @notice Interface for Broker with tuple -> struct casting
 * @dev This is used to access the internal trading limits state and
 * config as structs as opposed to tuples.
 */
interface IBrokerWithCasts {
  function tradingLimitsState(bytes32 id) external view returns (TradingLimits.State memory);

  function tradingLimitsConfig(bytes32 id) external view returns (TradingLimits.Config memory);
}

library Utils {
  using FixidityLib for FixidityLib.Fraction;
  using TradingLimits for TradingLimits.State;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  struct Context {
    BaseForkTest t;
    Broker broker;
    IBrokerWithCasts brokerWithCasts;
    SortedOracles sortedOracles;
    BreakerBox breakerBox;
    address exchangeProvider;
    bytes32 exchangeId;
    IExchangeProvider.Exchange exchange;
  }

  function newContext(address _t, uint256 index) public view returns (Context memory ctx) {
    BaseForkTest t = BaseForkTest(_t);
    (address exchangeProvider, IExchangeProvider.Exchange memory exchange) = t.exchanges(index);

    ctx = Context(
      t,
      t.broker(),
      IBrokerWithCasts(address(t.broker())),
      t.sortedOracles(),
      t.breakerBox(),
      exchangeProvider,
      exchange.exchangeId,
      exchange
    );
  }

  // ========================= Swaps =========================

  function swapIn(
    Context memory ctx,
    address from,
    address to,
    uint256 sellAmount
  ) public returns (uint256) {
    ctx.t.mint(from, ctx.t.trader0(), sellAmount);
    IERC20Metadata(from).approve(address(ctx.broker), sellAmount);

    uint256 minAmountOut = ctx.broker.getAmountOut(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount);
    return ctx.broker.swapIn(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount, minAmountOut);
  }

  function swapOut(
    Context memory ctx,
    address from,
    address to,
    uint256 buyAmount
  ) public returns (uint256) {
    uint256 maxAmountIn = ctx.broker.getAmountIn(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount);

    ctx.t.mint(from, ctx.t.trader0(), maxAmountIn);
    IERC20Metadata(from).approve(address(ctx.broker), maxAmountIn);

    return ctx.broker.swapOut(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount, maxAmountIn);
  }

  // ========================= Sorted Oracles =========================

  function getReferenceRateFraction(Context memory ctx, address baseAsset)
    internal
    view
    returns (FixidityLib.Fraction memory)
  {
    (uint256 numerator, uint256 denominator) = getReferenceRate(ctx);
    address asset0 = ctx.exchange.assets[0];
    if (baseAsset == asset0) {
      return FixidityLib.newFixedFraction(numerator, denominator);
    }
    return FixidityLib.newFixedFraction(denominator, numerator);
  }

  function getReferenceRate(Context memory ctx) internal view returns (uint256, uint256) {
    uint256 rateNumerator;
    uint256 rateDenominator;
    (rateNumerator, rateDenominator) = ctx.sortedOracles.medianRate(getReferenceRateFeedID(ctx));
    require(rateDenominator > 0, "exchange rate denominator must be greater than 0");
    return (rateNumerator, rateDenominator);
  }

  function getReferenceRateFeedID(Context memory ctx) internal view returns (address) {
    // TODO: extend this when we have multiple exchange providers, for now assume it's a BiPoolManager
    BiPoolManager biPoolManager = BiPoolManager(ctx.exchangeProvider);
    BiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(ctx.exchangeId);
    return pool.config.referenceRateFeedID;
  }

  function getValueDeltaBreakerReferenceValue(Context memory ctx, address _breaker)
    internal
    view
    returns (uint256)
  {
    ValueDeltaBreaker breaker = ValueDeltaBreaker(_breaker);
    address rateFeedID = getReferenceRateFeedID(ctx);
    return breaker.referenceValues(rateFeedID);
  }

  function getBreakerRateChangeThreshold(Context memory ctx, address _breaker)
    internal
    view
    returns (uint256)
  {
    MedianDeltaBreaker breaker = MedianDeltaBreaker(_breaker);
    address rateFeedID = getReferenceRateFeedID(ctx);

    uint256 rateChangeThreshold = breaker.defaultRateChangeThreshold();
    uint256 specificRateChangeThreshold = breaker.rateChangeThreshold(rateFeedID);
    if (specificRateChangeThreshold != 0) {
      rateChangeThreshold = specificRateChangeThreshold;
    }
    return rateChangeThreshold;
  }

  // ========================= Trading Limits =========================

  function isLimitConfigured(Context memory ctx, bytes32 limitId) public view returns (bool) {
    TradingLimits.Config memory limitConfig = ctx.brokerWithCasts.tradingLimitsConfig(limitId);
    return limitConfig.flags > uint8(0);
  }

  function tradingLimitsConfig(Context memory ctx, bytes32 limitId) public view returns (TradingLimits.Config memory) {
    return ctx.brokerWithCasts.tradingLimitsConfig(limitId);
  }

  function tradingLimitsState(Context memory ctx, bytes32 limitId) public view returns (TradingLimits.State memory) {
    return ctx.brokerWithCasts.tradingLimitsState(limitId);
  }

  function tradingLimitsConfig(Context memory ctx, address asset) public view returns (TradingLimits.Config memory) {
    bytes32 assetBytes32 = bytes32(uint256(uint160(asset)));
    return ctx.brokerWithCasts.tradingLimitsConfig(ctx.exchangeId ^ assetBytes32);
  }

  function tradingLimitsState(Context memory ctx, address asset) public view returns (TradingLimits.State memory) {
    bytes32 assetBytes32 = bytes32(uint256(uint160(asset)));
    return ctx.brokerWithCasts.tradingLimitsState(ctx.exchangeId ^ assetBytes32);
  }

  function refreshedTradingLimitsState(Context memory ctx, address asset)
    public
    view
    returns (TradingLimits.State memory)
  {
    TradingLimits.Config memory config = tradingLimitsConfig(ctx, asset);
    // Netflow might be outdated because of a skip(...) call and doing
    // an update(0) would reset the netflow if enough time has passed.
    return tradingLimitsState(ctx, asset).update(config, 0, 0);
  }

  function isLimitEnabled(TradingLimits.Config memory config, uint8 limit) internal returns (bool) {
    return (config.flags & limit) > 0;
  }

  function getLimit(TradingLimits.Config memory config, uint8 limit) internal returns (int48) {
    if (limit == L0) {
      return config.limit0;
    } else if (limit == L1) {
      return config.limit1;
    } else if (limit == LG) {
      return config.limitGlobal;
    } else {
      revert("invalid limit");
    }
  }

  function getNetflow(TradingLimits.State memory state, uint8 limit) internal returns (int48) {
    if (limit == L0) {
      return state.netflow0;
    } else if (limit == L1) {
      return state.netflow1;
    } else if (limit == LG) {
      return state.netflowGlobal;
    } else {
      revert("invalid limit");
    }
  }

  function revertReason(uint8 limit) internal returns (string memory) {
    if (limit == L0) {
      return "L0 Exceeded";
    } else if (limit == L1) {
      return "L1 Exceeded";
    } else if (limit == LG) {
      return "LG Exceeded";
    } else {
      revert("invalid limit");
    }
  }

  // ========================= Oracles =========================

  function getOraclesCount(Context memory ctx, address rateFeedID) public view returns (uint256) {}

  // ========================= Misc =========================

  function toSubunits(uint256 units, address token) internal view returns (uint256) {
    uint256 tokenBase = 10**uint256(IERC20Metadata(token).decimals());
    return units * tokenBase;
  }
}