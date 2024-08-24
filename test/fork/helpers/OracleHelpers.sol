// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { console } from "forge-std/console.sol";
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { ExchangeForkTest } from "../ExchangeForkTest.sol";

import { IExchangeProvider } from "contracts/interfaces/IExchangeProvider.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IMedianDeltaBreaker } from "contracts/interfaces/IMedianDeltaBreaker.sol";
import { IValueDeltaBreaker } from "contracts/interfaces/IValueDeltaBreaker.sol";

library OracleHelpers {
  function getReferenceRate(ExchangeForkTest ctx) internal view returns (uint256, uint256) {
    uint256 rateNumerator;
    uint256 rateDenominator;
    (rateNumerator, rateDenominator) = ctx.sortedOracles().medianRate(ctx.rateFeedId());
    require(rateDenominator > 0, "exchange rate denominator must be greater than 0");
    return (rateNumerator, rateDenominator);
  }

  function getReferenceRateFraction(
    ExchangeForkTest ctx,
    address baseAsset
  ) internal view returns (FixidityLib.Fraction memory) {
    (uint256 numerator, uint256 denominator) = getReferenceRate(ctx);
    address asset0 = ctx.assets(0);
    if (baseAsset == asset0) {
      return FixidityLib.newFixedFraction(numerator, denominator);
    }
    return FixidityLib.newFixedFraction(denominator, numerator);
  }

  function shouldUpdateBuckets(ExchangeForkTest ctx) internal view returns (bool, bool, bool, bool, bool) {
    IBiPoolManager.PoolExchange memory exchange = ctx.getPool();
    // address addr = ctx.poolExchange();
    // console.log("addr: %s", addr);
    // IBiPoolManager.PoolExchange memory exchange

    (bool isReportExpired, ) = ctx.sortedOracles().isOldestReportExpired(exchange.config.referenceRateFeedID);
    // solhint-disable-next-line not-rely-on-time
    bool timePassed = block.timestamp >= exchange.lastBucketUpdate + exchange.config.referenceRateResetFrequency;
    bool enoughReports = (ctx.sortedOracles().numRates(exchange.config.referenceRateFeedID) >=
      exchange.config.minimumReports);
    // solhint-disable-next-line not-rely-on-time
    bool medianReportRecent = ctx.sortedOracles().medianTimestamp(exchange.config.referenceRateFeedID) >
      block.timestamp - exchange.config.referenceRateResetFrequency;

    return (
      timePassed,
      enoughReports,
      medianReportRecent,
      isReportExpired,
      timePassed && enoughReports && medianReportRecent && !isReportExpired
    );
  }

  function newMedianToResetBreaker(
    ExchangeForkTest ctx,
    uint256 breakerIndex
  ) internal view returns (uint256 newMedian) {
    address[] memory _breakers = ctx.breakerBox().getBreakers();
    bool isMedianDeltaBreaker = breakerIndex == 0;
    bool isValueDeltaBreaker = breakerIndex == 1;
    if (isMedianDeltaBreaker) {
      uint256 currentEMA = IMedianDeltaBreaker(_breakers[breakerIndex]).medianRatesEMA(ctx.rateFeedId());
      return currentEMA;
    } else if (isValueDeltaBreaker) {
      return IValueDeltaBreaker(_breakers[breakerIndex]).referenceValues(ctx.rateFeedId());
    } else {
      revert("can't infer corresponding breaker");
    }
  }

  function getBreakerRateChangeThreshold(ExchangeForkTest ctx, address _breaker) internal view returns (uint256) {
    IMedianDeltaBreaker breaker = IMedianDeltaBreaker(_breaker);

    uint256 rateChangeThreshold = breaker.defaultRateChangeThreshold();
    uint256 specificRateChangeThreshold = breaker.rateChangeThreshold(ctx.rateFeedId());
    if (specificRateChangeThreshold != 0) {
      rateChangeThreshold = specificRateChangeThreshold;
    }
    return rateChangeThreshold;
  }

  function getUpdatedBuckets(ExchangeForkTest ctx) internal view returns (uint256 bucket0, uint256 bucket1) {
    IBiPoolManager.PoolExchange memory exchange = ctx.getPool();

    bucket0 = exchange.config.stablePoolResetSize;
    uint256 exchangeRateNumerator;
    uint256 exchangeRateDenominator;
    (exchangeRateNumerator, exchangeRateDenominator) = getReferenceRate(ctx);

    bucket1 = (exchangeRateDenominator * bucket0) / exchangeRateNumerator;
  }
}
