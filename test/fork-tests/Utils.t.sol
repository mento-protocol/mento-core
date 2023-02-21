// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { BaseForkTest } from "./BaseForkTest.t.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";

import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";
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
  using SafeMath for uint256;
  using FixidityLib for FixidityLib.Fraction;
  using TradingLimits for TradingLimits.State;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  address constant private VM_ADDRESS =
    address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));

  Vm public constant vm = Vm(VM_ADDRESS);

  struct Context {
    BaseForkTest t;
    Broker broker;
    IBrokerWithCasts brokerWithCasts;
    SortedOracles sortedOracles;
    BreakerBox breakerBox;
    address exchangeProvider;
    bytes32 exchangeId;
    IExchangeProvider.Exchange exchange;
    address trader;
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
      exchange,
      t.trader()
    );
  }

  // ========================= Swaps =========================

  function swapIn(
    Context memory ctx,
    address from,
    address to,
    uint256 sellAmount
  ) public returns (uint256) {
    ctx.t.mint(from, ctx.trader, sellAmount);
    changePrank(ctx.trader);
    IERC20Metadata(from).approve(address(ctx.broker), sellAmount);

    addReportsIfNeeded(ctx);
    uint256 minAmountOut = ctx.broker.getAmountOut(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount);
    return ctx.broker.swapIn(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount, minAmountOut);
  }

  function swapOut(
    Context memory ctx,
    address from,
    address to,
    uint256 buyAmount
  ) public returns (uint256) {
    addReportsIfNeeded(ctx);
    uint256 maxAmountIn = ctx.broker.getAmountIn(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount);

    ctx.t.mint(from, ctx.trader, maxAmountIn);
    changePrank(ctx.trader);
    IERC20Metadata(from).approve(address(ctx.broker), maxAmountIn);

    return ctx.broker.swapOut(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount, maxAmountIn);
  }

  function addReportsIfNeeded(
    Context memory ctx
  ) internal {
    // TODO: extend this when we have multiple exchange providers, for now assume it's a BiPoolManager
    BiPoolManager biPoolManager = BiPoolManager(ctx.exchangeProvider);
    BiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(ctx.exchangeId);
    (bool isReportExpired, ) = ctx.sortedOracles.isOldestReportExpired(pool.config.referenceRateFeedID);

    // solhint-disable-next-line not-rely-on-time
    bool timePassed = now >= pool.lastBucketUpdate.add(pool.config.referenceRateResetFrequency);
    bool enoughReports = (ctx.sortedOracles.numRates(pool.config.referenceRateFeedID) >=
      pool.config.minimumReports);
    // solhint-disable-next-line not-rely-on-time
    bool medianReportRecent = ctx.sortedOracles.medianTimestamp(pool.config.referenceRateFeedID) >
      now.sub(pool.config.referenceRateResetFrequency);
    
    console.log(
      "\t timePassed: %s | enoughReports: %s",
      timePassed ? "true" : "false",
      enoughReports ? "true" : "false"
    );
    console.log(
      "\t medianReportRecent: %s | !isReportExpired: %s", 
      medianReportRecent ? "true" : "false",
      !isReportExpired ? "true" : "false"
    );
    console.log(
      "\t pool.bucket0: %d | pool.bucket1: %d", 
      pool.bucket0,
      pool.bucket1
    );
    console.log(
      "\t pool.lastBucketUpdate: %d",
      pool.lastBucketUpdate
    );

    if (timePassed && (!medianReportRecent || isReportExpired)) {
      (uint256 newMedian,) = ctx.sortedOracles.medianRate(pool.config.referenceRateFeedID);
      updateOracleMedianRate(ctx, newMedian.mul(101).div(100));

      (isReportExpired, ) = ctx.sortedOracles.isOldestReportExpired(pool.config.referenceRateFeedID);
      // solhint-disable-next-line not-rely-on-time
      timePassed = now >= pool.lastBucketUpdate.add(pool.config.referenceRateResetFrequency);
      enoughReports = (ctx.sortedOracles.numRates(pool.config.referenceRateFeedID) >=
        pool.config.minimumReports);
      // solhint-disable-next-line not-rely-on-time
      medianReportRecent = ctx.sortedOracles.medianTimestamp(pool.config.referenceRateFeedID) >
        now.sub(pool.config.referenceRateResetFrequency);
    
      console.log(
        "\t timePassed: %s | enoughReports: %s",
        timePassed ? "true" : "false",
        enoughReports ? "true" : "false"
      );
      console.log(
        "\t medianReportRecent: %s | !isReportExpired: %s", 
        medianReportRecent ? "true" : "false",
        !isReportExpired ? "true" : "false"
      );
      return;
    }
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

  function updateOracleMedianRate(Context memory ctx, uint256 newMedian) internal {
    address rateFeedID = getReferenceRateFeedID(ctx);
    address[] memory oracles = ctx.sortedOracles.getOracles(rateFeedID);
    require(oracles.length > 0, "No oracles for rateFeedID");
    console.log("Updating oracles to new median: ", newMedian);
    for (uint256 i = 0; i < oracles.length; i++) {
      skip(5);
      address oracle = oracles[i];
      address lesserKey;
      address greaterKey;
      (address[] memory keys, uint256[] memory values, ) = ctx.sortedOracles.getRates(rateFeedID);
      for (uint256 j = 0; j < keys.length; j++) {
        if (keys[j] == oracle) continue;
        if (values[j] < newMedian) lesserKey = keys[j];
        if (values[j] >= newMedian) greaterKey = keys[j];
      }

      console.log("Updating oracle: %s to new median: %s", oracle, newMedian);
      changePrank(oracle);
      ctx.sortedOracles.report(rateFeedID, newMedian, lesserKey, greaterKey);
    }
    changePrank(ctx.trader);
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

  function isLimitEnabled(TradingLimits.Config memory config, uint8 limit) internal pure returns (bool) {
    return (config.flags & limit) > 0;
  }

  function getLimit(TradingLimits.Config memory config, uint8 limit) internal pure returns (int48) {
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

  function getNetflow(TradingLimits.State memory state, uint8 limit) internal pure returns (int48) {
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

  function revertReason(uint8 limit) internal pure returns (string memory) {
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

  function getOraclesCount(Context memory ctx, address rateFeedID) public view returns (uint256) {}

  // ========================= Misc =========================

  function toSubunits(uint256 units, address token) internal view returns (uint256) {
    uint256 tokenBase = 10**uint256(IERC20Metadata(token).decimals());
    return units * tokenBase;
  }

  // ==================== Forge Cheats ======================
  // Pulling in some test helpers to not have to expose them in 
  // the test contract

  function skip(uint256 time) internal {
    vm.warp(block.timestamp + time);
  }

  function changePrank(address who) internal {
    vm.stopPrank();
    vm.startPrank(who);
  }
}
