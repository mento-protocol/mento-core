// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;
pragma experimental ABIEncoderV2;

import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { VM_ADDRESS } from "mento-std/Constants.sol";

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

import { BaseForkTest } from "./BaseForkTest.sol";

import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { IBroker } from "contracts/interfaces/IBroker.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IMedianDeltaBreaker } from "contracts/interfaces/IMedianDeltaBreaker.sol";
import { IValueDeltaBreaker } from "contracts/interfaces/IValueDeltaBreaker.sol";
import { ITradingLimitsHarness } from "test/harnesses/ITradingLimitsHarness.sol";

library Utils {
  using FixidityLib for FixidityLib.Fraction;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  Vm public constant vm = Vm(VM_ADDRESS);

  struct Context {
    BaseForkTest t;
    IBroker broker;
    ISortedOracles sortedOracles;
    IBreakerBox breakerBox;
    address exchangeProvider;
    bytes32 exchangeId;
    address rateFeedID;
    IExchangeProvider.Exchange exchange;
    address trader;
    ITradingLimitsHarness tradingLimits;
  }

  function newContext(address _t, uint256 index) public view returns (Context memory ctx) {
    BaseForkTest t = BaseForkTest(_t);
    (address exchangeProvider, IExchangeProvider.Exchange memory exchange) = t.exchanges(index);

    ctx = Context(
      t,
      t.broker(),
      t.sortedOracles(),
      t.breakerBox(),
      exchangeProvider,
      exchange.exchangeId,
      address(0),
      exchange,
      t.trader(),
      t.tradingLimits()
    );
  }

  function newRateFeedContext(address _t, address rateFeed) public view returns (Context memory ctx) {
    BaseForkTest t = BaseForkTest(_t);

    ctx = Context(
      t,
      t.broker(),
      t.sortedOracles(),
      t.breakerBox(),
      address(0),
      bytes32(0),
      rateFeed,
      IExchangeProvider.Exchange(0, new address[](0)),
      t.trader(),
      t.tradingLimits()
    );
  }

  function getContextForRateFeedID(address _t, address rateFeedID) public view returns (Context memory) {
    BaseForkTest t = BaseForkTest(_t);
    (address biPoolManagerAddr, ) = t.exchanges(0);
    uint256 nOfExchanges = IBiPoolManager(biPoolManagerAddr).getExchanges().length;
    for (uint256 i = 0; i < nOfExchanges; i++) {
      Context memory ctx = newContext(_t, i);
      if (getReferenceRateFeedID(ctx) == rateFeedID) {
        return ctx;
      }
    }
    return newRateFeedContext(_t, rateFeedID);
  }

  // ========================= Swaps =========================

  function swapIn(Context memory ctx, address from, address to, uint256 sellAmount) public returns (uint256) {
    ctx.t._deal(from, ctx.trader, sellAmount, true);
    changePrank(ctx.trader);
    IERC20(from).approve(address(ctx.broker), sellAmount);

    addReportsIfNeeded(ctx);
    uint256 minAmountOut = ctx.broker.getAmountOut(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount);
    console.log(
      string(
        abi.encodePacked(unicode"🤝 swapIn(", toSymbol(from), "->", toSymbol(to), ", amountIn: %d, minAmountOut:%d)")
      ),
      toUnits(sellAmount, from),
      toUnits(minAmountOut, to)
    );
    return ctx.broker.swapIn(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount, minAmountOut);
  }

  function swapOut(Context memory ctx, address from, address to, uint256 buyAmount) public returns (uint256) {
    addReportsIfNeeded(ctx);
    uint256 maxAmountIn = ctx.broker.getAmountIn(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount);

    ctx.t._deal(from, ctx.trader, maxAmountIn, true);
    changePrank(ctx.trader);
    IERC20(from).approve(address(ctx.broker), maxAmountIn);

    console.log(
      string(
        abi.encodePacked(unicode"🤝 swapOut(", toSymbol(from), "->", toSymbol(to), ",amountOut: %d, maxAmountIn: %d)")
      ),
      toUnits(buyAmount, to),
      toUnits(maxAmountIn, from)
    );
    return ctx.broker.swapOut(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount, maxAmountIn);
  }

  function shouldUpdateBuckets(Context memory ctx) internal view returns (bool, bool, bool, bool, bool) {
    IBiPoolManager biPoolManager = IBiPoolManager(ctx.exchangeProvider);
    IBiPoolManager.PoolExchange memory exchange = biPoolManager.getPoolExchange(ctx.exchangeId);

    (bool isReportExpired, ) = ctx.sortedOracles.isOldestReportExpired(exchange.config.referenceRateFeedID);
    // solhint-disable-next-line not-rely-on-time
    bool timePassed = block.timestamp >= exchange.lastBucketUpdate + exchange.config.referenceRateResetFrequency;
    bool enoughReports = (ctx.sortedOracles.numRates(exchange.config.referenceRateFeedID) >=
      exchange.config.minimumReports);
    // solhint-disable-next-line not-rely-on-time
    bool medianReportRecent = ctx.sortedOracles.medianTimestamp(exchange.config.referenceRateFeedID) >
      block.timestamp - exchange.config.referenceRateResetFrequency;

    return (
      timePassed,
      enoughReports,
      medianReportRecent,
      isReportExpired,
      timePassed && enoughReports && medianReportRecent && !isReportExpired
    );
  }

  function getUpdatedBuckets(Context memory ctx) internal view returns (uint256 bucket0, uint256 bucket1) {
    IBiPoolManager biPoolManager = IBiPoolManager(ctx.exchangeProvider);
    IBiPoolManager.PoolExchange memory exchange = biPoolManager.getPoolExchange(ctx.exchangeId);

    bucket0 = exchange.config.stablePoolResetSize;
    uint256 exchangeRateNumerator;
    uint256 exchangeRateDenominator;
    (exchangeRateNumerator, exchangeRateDenominator) = getReferenceRate(ctx);

    bucket1 = (exchangeRateDenominator * bucket0) / exchangeRateNumerator;
  }

  function addReportsIfNeeded(Context memory ctx) internal {
    // TODO: extend this when we have multiple exchange providers, for now assume it's a BiPoolManager
    IBiPoolManager biPoolManager = IBiPoolManager(ctx.exchangeProvider);
    IBiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(ctx.exchangeId);
    (bool timePassed, bool enoughReports, bool medianReportRecent, bool isReportExpired, ) = shouldUpdateBuckets(ctx);
    // logPool(ctx);
    if (timePassed && (!medianReportRecent || isReportExpired || !enoughReports)) {
      (uint256 newMedian, ) = ctx.sortedOracles.medianRate(pool.config.referenceRateFeedID);
      (timePassed, enoughReports, medianReportRecent, isReportExpired, ) = shouldUpdateBuckets(ctx);
      updateOracleMedianRate(ctx, (newMedian * 1_000_001) / 1_000_000);

      // logPool(ctx);
      return;
    }
  }

  function maxSwapIn(
    Context memory ctx,
    uint256 desired,
    address from,
    address to
  ) internal view returns (uint256 maxPossible) {
    // TODO: extend this when we have multiple exchange providers, for now assume it's a BiPoolManager
    IBiPoolManager biPoolManager = IBiPoolManager(ctx.exchangeProvider);
    IBiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(ctx.exchangeId);
    uint256 toBucket = (pool.asset0 == to ? pool.bucket0 : pool.bucket1) - 1;
    (, , , , bool shouldUpdate) = shouldUpdateBuckets(ctx);
    if (shouldUpdate) {
      (uint256 bucket0, uint256 bucket1) = getUpdatedBuckets(ctx);
      toBucket = (pool.asset0 == to ? bucket0 : bucket1) - 1;
    }
    toBucket = toBucket / biPoolManager.tokenPrecisionMultipliers(to);
    maxPossible = ctx.broker.getAmountIn(ctx.exchangeProvider, ctx.exchangeId, from, to, toBucket);
    if (maxPossible > desired) {
      maxPossible = desired;
    }
  }

  function maxSwapOut(Context memory ctx, uint256 desired, address to) internal view returns (uint256 maxPossible) {
    // TODO: extend this when we have multiple exchange providers, for now assume it's a BiPoolManager
    IBiPoolManager biPoolManager = IBiPoolManager(ctx.exchangeProvider);
    IBiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(ctx.exchangeId);
    uint256 maxPossible_ = (pool.asset0 == to ? pool.bucket0 : pool.bucket1) - 1;
    (, , , , bool shouldUpdate) = shouldUpdateBuckets(ctx);
    if (shouldUpdate) {
      (uint256 bucket0, uint256 bucket1) = getUpdatedBuckets(ctx);
      maxPossible_ = (pool.asset0 == to ? bucket0 : bucket1) - 1;
    }
    maxPossible = maxPossible / biPoolManager.tokenPrecisionMultipliers(to);
    if (maxPossible > desired) {
      maxPossible = desired;
    }
  }

  // ========================= Sorted Oracles =========================

  function getReferenceRateFraction(
    Context memory ctx,
    address baseAsset
  ) internal view returns (FixidityLib.Fraction memory) {
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
    if (ctx.rateFeedID != address(0)) {
      return ctx.rateFeedID;
    }
    // TODO: extend this when we have multiple exchange providers, for now assume it's a BiPoolManager
    IBiPoolManager biPoolManager = IBiPoolManager(ctx.exchangeProvider);
    IBiPoolManager.PoolExchange memory pool = biPoolManager.getPoolExchange(ctx.exchangeId);
    return pool.config.referenceRateFeedID;
  }

  function getValueDeltaBreakerReferenceValue(Context memory ctx, address _breaker) internal view returns (uint256) {
    IValueDeltaBreaker breaker = IValueDeltaBreaker(_breaker);
    address rateFeedID = getReferenceRateFeedID(ctx);
    return breaker.referenceValues(rateFeedID);
  }

  function getBreakerRateChangeThreshold(Context memory ctx, address _breaker) internal view returns (uint256) {
    IMedianDeltaBreaker breaker = IMedianDeltaBreaker(_breaker);
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
    console.log(unicode"🔮 Updating oracles to new median: ", newMedian);
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

      changePrank(oracle);
      ctx.sortedOracles.report(rateFeedID, newMedian, lesserKey, greaterKey);
    }
    console.log("done with updateOracleMedianRate");
    changePrank(ctx.trader);
  }

  // ========================= Trading Limits =========================

  function isLimitConfigured(Context memory ctx, bytes32 limitId) public view returns (bool) {
    ITradingLimits.Config memory limitConfig = ctx.broker.tradingLimitsConfig(limitId);
    return limitConfig.flags > uint8(0);
  }

  function tradingLimitsConfig(Context memory ctx, bytes32 limitId) public view returns (ITradingLimits.Config memory) {
    return ctx.broker.tradingLimitsConfig(limitId);
  }

  function tradingLimitsState(Context memory ctx, bytes32 limitId) public view returns (ITradingLimits.State memory) {
    return ctx.broker.tradingLimitsState(limitId);
  }

  function tradingLimitsConfig(Context memory ctx, address asset) public view returns (ITradingLimits.Config memory) {
    bytes32 assetBytes32 = bytes32(uint256(uint160(asset)));
    return ctx.broker.tradingLimitsConfig(ctx.exchangeId ^ assetBytes32);
  }

  function tradingLimitsState(Context memory ctx, address asset) public view returns (ITradingLimits.State memory) {
    bytes32 assetBytes32 = bytes32(uint256(uint160(asset)));
    return ctx.broker.tradingLimitsState(ctx.exchangeId ^ assetBytes32);
  }

  function refreshedTradingLimitsState(
    Context memory ctx,
    address asset
  ) public view returns (ITradingLimits.State memory) {
    ITradingLimits.Config memory config = tradingLimitsConfig(ctx, asset);
    // Netflow might be outdated because of a skip(...) call and doing
    // an update(0) would reset the netflow if enough time has passed.
    return ctx.tradingLimits.update(tradingLimitsState(ctx, asset), config, 0, 0);
  }

  function isLimitEnabled(ITradingLimits.Config memory config, uint8 limit) internal pure returns (bool) {
    return (config.flags & limit) > 0;
  }

  function getLimit(ITradingLimits.Config memory config, uint8 limit) internal pure returns (uint256) {
    if (limit == L0) {
      return uint256(int256(config.limit0));
    } else if (limit == L1) {
      return uint256(int256(config.limit1));
    } else if (limit == LG) {
      return uint256(int256(config.limitGlobal));
    } else {
      revert("invalid limit");
    }
  }

  function getNetflow(ITradingLimits.State memory state, uint8 limit) internal pure returns (int256) {
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

  function limitString(uint8 limit) internal pure returns (string memory) {
    if (limit == L0) {
      return "L0";
    } else if (limit == L1) {
      return "L1";
    } else if (limit == LG) {
      return "LG";
    } else {
      revert("invalid limit");
    }
  }

  function maxPossibleInflow(Context memory ctx, address from) internal view returns (int48) {
    ITradingLimits.Config memory limitConfig = tradingLimitsConfig(ctx, from);
    ITradingLimits.State memory limitState = refreshedTradingLimitsState(ctx, from);
    int48 maxInflowL0 = limitConfig.limit0 - limitState.netflow0;
    int48 maxInflowL1 = limitConfig.limit1 - limitState.netflow1;
    int48 maxInflowLG = limitConfig.limitGlobal - limitState.netflowGlobal;

    if (limitConfig.flags == L0 | L1 | LG) {
      return min(maxInflowL0, maxInflowL1, maxInflowLG);
    } else if (limitConfig.flags == L0 | LG) {
      return min(maxInflowL0, maxInflowLG);
    } else if (limitConfig.flags == L0 | L1) {
      return min(maxInflowL0, maxInflowL1);
    } else if (limitConfig.flags == L0) {
      return maxInflowL0;
    } else {
      revert("Unexpected limit config");
    }
  }

  function maxPossibleOutflow(Context memory ctx, address to) internal view returns (int48) {
    ITradingLimits.Config memory limitConfig = tradingLimitsConfig(ctx, to);
    ITradingLimits.State memory limitState = refreshedTradingLimitsState(ctx, to);
    int48 maxOutflowL0 = limitConfig.limit0 + limitState.netflow0 - 1;
    int48 maxOutflowL1 = limitConfig.limit1 + limitState.netflow1 - 1;
    int48 maxOutflowLG = limitConfig.limitGlobal + limitState.netflowGlobal - 1;

    if (limitConfig.flags == L0 | L1 | LG) {
      return min(maxOutflowL0, maxOutflowL1, maxOutflowLG);
    } else if (limitConfig.flags == L0 | LG) {
      return min(maxOutflowL0, maxOutflowLG);
    } else if (limitConfig.flags == L0 | L1) {
      return min(maxOutflowL0, maxOutflowL1);
    } else if (limitConfig.flags == L0) {
      return maxOutflowL0;
    } else {
      revert("Unexpected limit config");
    }
  }

  // ========================= Misc =========================

  function toSubunits(uint256 units, address token) internal view returns (uint256) {
    uint256 tokenBase = 10 ** uint256(IERC20(token).decimals());
    return units * tokenBase;
  }

  function toUnits(uint256 subunits, address token) internal view returns (uint256) {
    uint256 tokenBase = 10 ** uint256(IERC20(token).decimals());
    return subunits / tokenBase;
  }

  function toUnitsFixed(uint256 subunits, address token) internal view returns (FixidityLib.Fraction memory) {
    uint256 tokenBase = 10 ** uint256(IERC20(token).decimals());
    return FixidityLib.newFixedFraction(subunits, tokenBase);
  }

  function toSymbol(address token) internal view returns (string memory) {
    return IERC20(token).symbol();
  }

  function ticker(Context memory ctx) internal view returns (string memory) {
    return
      string(abi.encodePacked(IERC20(ctx.exchange.assets[0]).symbol(), "/", IERC20(ctx.exchange.assets[1]).symbol()));
  }

  function logHeader(Context memory ctx) internal view {
    console.log("========================================");
    console.log(unicode"🔦 Testing pair:", ticker(ctx));
    console.log("========================================");
  }

  function min(int48 a, int48 b) internal pure returns (int48) {
    return a > b ? b : a;
  }

  function min(int48 a, int48 b, int48 c) internal pure returns (int48) {
    return min(a, min(b, c));
  }

  function logPool(Context memory ctx) internal view {
    if (ctx.exchangeId == 0) {
      console.log(unicode"🎱 RateFeed: %s", ctx.rateFeedID);
      return;
    }
    IBiPoolManager biPoolManager = IBiPoolManager(ctx.exchangeProvider);
    IBiPoolManager.PoolExchange memory exchange = biPoolManager.getPoolExchange(ctx.exchangeId);

    (bool timePassed, bool enoughReports, bool medianReportRecent, bool isReportExpired, ) = shouldUpdateBuckets(ctx);
    console.log(unicode"🎱 Pool: %s", ticker(ctx));
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
      "\t exchange.bucket0: %d | exchange.bucket1: %d",
      toUnits(exchange.bucket0, exchange.asset0),
      toUnits(exchange.bucket1, exchange.asset1)
    );
    console.log("\t exchange.lastBucketUpdate: %d", exchange.lastBucketUpdate);
  }

  function logNetflows(Context memory ctx, address target) internal view {
    ITradingLimits.State memory limitState = tradingLimitsState(ctx, target);
    console.log(
      "\t netflow0: %s%d",
      limitState.netflow0 < 0 ? "-" : "",
      uint256(int256(limitState.netflow0 < 0 ? limitState.netflow0 * -1 : limitState.netflow0))
    );
    console.log(
      "\t netflow1: %s%d",
      limitState.netflow1 < 0 ? "-" : "",
      uint256(int256(limitState.netflow1 < 0 ? limitState.netflow1 * -1 : limitState.netflow1))
    );
    console.log(
      "\t netflowGlobal: %s%d",
      limitState.netflowGlobal < 0 ? "-" : "",
      uint256(int256(limitState.netflowGlobal < 0 ? limitState.netflowGlobal * -1 : limitState.netflowGlobal))
    );
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
