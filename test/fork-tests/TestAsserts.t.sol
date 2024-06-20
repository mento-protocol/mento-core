// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { SafeMath } from "openzeppelin-solidity/contracts/math/SafeMath.sol";

import { Test } from "celo-foundry/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { Utils } from "./Utils.t.sol";

import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";
import { IBreaker } from "contracts/interfaces/IBreaker.sol";

import { BiPoolManager } from "contracts/swap/BiPoolManager.sol";
import { WithCooldown } from "contracts/oracles/breakers/WithCooldown.sol";
import { MedianDeltaBreaker } from "contracts/oracles/breakers/MedianDeltaBreaker.sol";
import { ValueDeltaBreaker } from "contracts/oracles/breakers/ValueDeltaBreaker.sol";

contract TestAsserts is Test {
  using Utils for Utils.Context;
  using Utils for TradingLimits.Config;
  using Utils for TradingLimits.State;
  using Utils for uint8;
  using Utils for uint256;
  using SafeMath for uint256;
  // using TradingLimits for TradingLimits.State;
  // using TradingLimits for TradingLimits.Config;
  using FixidityLib for FixidityLib.Fraction;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  uint256 fixed1 = FixidityLib.fixed1().unwrap();
  FixidityLib.Fraction pc10 = FixidityLib.newFixedFraction(10, 100);

  // ========================= Swap Asserts ========================= //

  function assert_swapIn(Utils.Context memory ctx, address from, address to, uint256 sellAmount) internal {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);
    FixidityLib.Fraction memory amountIn = sellAmount.toUnitsFixed(from);
    FixidityLib.Fraction memory amountOut = ctx.swapIn(from, to, sellAmount).toUnitsFixed(to);
    FixidityLib.Fraction memory expectedAmountOut = amountIn.divide(rate);

    assertApproxEqAbs(amountOut.unwrap(), expectedAmountOut.unwrap(), pc10.multiply(expectedAmountOut).unwrap());
  }

  function assert_swapOut(Utils.Context memory ctx, address from, address to, uint256 buyAmount) internal {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);
    FixidityLib.Fraction memory amountOut = buyAmount.toUnitsFixed(to);
    FixidityLib.Fraction memory amountIn = ctx.swapOut(from, to, buyAmount).toUnitsFixed(from);
    FixidityLib.Fraction memory expectedAmountIn = amountOut.multiply(rate);

    assertApproxEqAbs(amountIn.unwrap(), expectedAmountIn.unwrap(), pc10.multiply(expectedAmountIn).unwrap());
  }

  function assert_swapInFails(
    Utils.Context memory ctx,
    address from,
    address to,
    uint256 sellAmount,
    string memory revertReason
  ) internal {
    ctx.addReportsIfNeeded();
    ctx.t.mint(from, ctx.trader, sellAmount);
    IERC20Metadata(from).approve(address(ctx.broker), sellAmount);
    uint256 minAmountOut = ctx.broker.getAmountOut(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount);
    vm.expectRevert(bytes(revertReason));
    ctx.broker.swapIn(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount, minAmountOut);
  }

  function assert_swapOutFails(
    Utils.Context memory ctx,
    address from,
    address to,
    uint256 buyAmount,
    string memory revertReason
  ) internal {
    ctx.addReportsIfNeeded();
    uint256 maxAmountIn = ctx.broker.getAmountIn(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount);
    ctx.t.mint(from, ctx.trader, maxAmountIn);
    IERC20Metadata(from).approve(address(ctx.broker), maxAmountIn);
    vm.expectRevert(bytes(revertReason));
    ctx.broker.swapOut(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount, maxAmountIn);
  }

  // ========================= Trading Limit Asserts ========================= //

  function assert_swapOverLimitFails(Utils.Context memory ctx, address from, address to, uint8 limit) internal {
    TradingLimits.Config memory fromLimitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.Config memory toLimitConfig = ctx.tradingLimitsConfig(to);
    console.log(
      string(abi.encodePacked("Swapping ", IERC20Metadata(from).symbol(), " -> ", IERC20Metadata(to).symbol())),
      "with limit",
      limit.limitString()
    );
    console.log("========================================");

    if (fromLimitConfig.isLimitEnabled(limit) && toLimitConfig.isLimitEnabled(limit)) {
      // TODO: Figure out best way to implement fork tests
      // when two limits are configured.
      console.log("Both Limits enabled skipping for now");
    } else if (fromLimitConfig.isLimitEnabled(limit)) {
      assert_swapOverLimitFails_onInflow(ctx, from, to, limit);
    } else if (toLimitConfig.isLimitEnabled(limit)) {
      assert_swapOverLimitFails_onOutflow(ctx, from, to, limit);
    }
  }

  function assert_swapOverLimitFails_onInflow(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) internal {
    /*
     * L*[from] -> to
     * Assert that inflow on `from` is limited by the limit
     * which can be any of L0, L1, LG.
     * This is done by swapping from `from` to `to` until
     * just before the limit is reached, within the constraints of
     * the other limits, and then doing a final swap that fails.
     */

    if (limit == L0) {
      swapUntilL0_onInflow(ctx, from, to);
    } else if (limit == L1) {
      swapUntilL1_onInflow(ctx, from, to);
    } else if (limit == LG) {
      swapUntilLG_onInflow(ctx, from, to);
    } else {
      revert("Invalid limit");
    }

    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(from);

    uint256 inflowRequiredUnits = uint256(limitConfig.getLimit(limit) - limitState.getNetflow(limit)) + 1;
    console.log("Inflow required to pass limit: ", inflowRequiredUnits);
    assert_swapInFails(ctx, from, to, inflowRequiredUnits.toSubunits(from), limit.revertReason());
  }

  function assert_swapOverLimitFails_onOutflow(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) internal {
    /*
     * from -> L*[to]
     * Assert that outflow on `to` is limited by the limit
     * which can be any of L0, L1, LG.
     * This is done by swapping from `from` to `to` until
     * just before the limit is reached, within the constraints of
     * the other limits, and then doing a final swap that fails.
     */

    // This should do valid swaps until just before the limit is reached
    if (limit == L0) {
      swapUntilL0_onOutflow(ctx, from, to);
    } else if (limit == L1) {
      swapUntilL1_onOutflow(ctx, from, to);
    } else if (limit == LG) {
      swapUntilLG_onOutflow(ctx, from, to);
    } else {
      revert("Invalid limit");
    }

    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to);

    uint256 outflowRequiredUnits = uint256(limitConfig.getLimit(limit) + limitState.getNetflow(limit)) + 1;
    console.log("Outflow required: ", outflowRequiredUnits);
    assert_swapOutFails(ctx, from, to, outflowRequiredUnits.toSubunits(to), limit.revertReason());
  }

  function swapUntilL0_onInflow(Utils.Context memory ctx, address from, address to) internal {
    /*
     * L0[from] -> to
     * This function will do valid swaps until just before L0 is hit
     * during inflow on `from`, therfore we check the positive end
     * of the limit because `from` flows into the reserve.
     */

    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    console.log("🏷️ [%d] Swap until L0=%d on inflow", block.timestamp, uint256(limitConfig.limit0));
    uint256 maxPossible;
    uint256 maxPossibleUntilLimit;
    do {
      int48 maxPossibleUntilLimitUnits = ctx.maxPossibleInflow(from);
      require(maxPossibleUntilLimitUnits >= 0, "max possible trade amount is negative");
      maxPossibleUntilLimit = uint256(maxPossibleUntilLimitUnits).toSubunits(from);
      maxPossible = ctx.maxSwapIn(maxPossibleUntilLimit, from, to);

      if (maxPossible > 0) {
        ctx.swapIn(from, to, maxPossible);
      }
    } while (maxPossible > 0 && maxPossibleUntilLimit > maxPossible);
    ctx.logNetflows(from);
  }

  function swapUntilL1_onInflow(Utils.Context memory ctx, address from, address to) internal {
    /*
     * L1[from] -> to
     * This function will do valid swaps until just before L1 is hit
     * during inflow on `from`, therfore we check the positive end
     * of the limit because `from` flows into the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(from);
    console.log("🏷️ [%d] Swap until L1=%d on inflow", block.timestamp, uint256(limitConfig.limit1));
    int48 maxPerSwap = limitConfig.limit0;
    while (limitState.netflow1 + maxPerSwap <= limitConfig.limit1) {
      skip(limitConfig.timestep0 + 1);
      ensureRateActive(ctx); // needed because otherwise constantSum might revert if the median is stale due to the skip

      swapUntilL0_onInflow(ctx, from, to);
      limitConfig = ctx.tradingLimitsConfig(from);
      limitState = ctx.tradingLimitsState(from);
    }
    skip(limitConfig.timestep0 + 1);
    ensureRateActive(ctx);
  }

  function swapUntilLG_onInflow(Utils.Context memory ctx, address from, address to) internal {
    /*
     * L1[from] -> to
     * This function will do valid swaps until just before LG is hit
     * during inflow on `from`, therfore we check the positive end
     * of the limit because `from` flows into the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(from);
    console.log("🏷️ [%d] Swap until LG=%d on inflow", block.timestamp, uint256(limitConfig.limitGlobal));

    if (limitConfig.isLimitEnabled(L1)) {
      int48 maxPerSwap = limitConfig.limit0;
      while (limitState.netflowGlobal + maxPerSwap <= limitConfig.limitGlobal) {
        skip(limitConfig.timestep1 + 1);
        swapUntilL1_onInflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(from);
        limitState = ctx.tradingLimitsState(from);
      }
      skip(limitConfig.timestep1 + 1);
    } else if (limitConfig.isLimitEnabled(L0)) {
      int48 maxPerSwap = limitConfig.limit0;
      while (limitState.netflowGlobal + maxPerSwap <= limitConfig.limitGlobal) {
        skip(limitConfig.timestep0 + 1);
        swapUntilL0_onInflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(from);
        limitState = ctx.tradingLimitsState(from);
      }
      skip(limitConfig.timestep0 + 1);
    }
  }

  function swapUntilL0_onOutflow(Utils.Context memory ctx, address from, address to) public {
    /*
     * from -> L0[to]
     * This function will do valid swaps until just before L0 is hit
     * during outflow on `to`, therfore we check the negative end
     * of the limit because `to` flows out of the reserve.
     */

    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    console.log("🏷️ [%d] Swap until L0=%d on outflow", block.timestamp, uint256(limitConfig.limit0));
    uint256 maxPossible;
    uint256 maxPossibleUntilLimit;
    do {
      int48 maxPossibleUntilLimitUnits = ctx.maxPossibleOutflow(to);
      require(maxPossibleUntilLimitUnits >= 0, "max possible trade amount is negative");
      maxPossibleUntilLimit = uint256(maxPossibleUntilLimitUnits).toSubunits(to);
      maxPossible = ctx.maxSwapOut(maxPossibleUntilLimit, to);

      if (maxPossible > 0) {
        ctx.swapOut(from, to, maxPossible);
      }
    } while (maxPossible > 0 && maxPossibleUntilLimit > maxPossible);
    ctx.logNetflows(to);
  }

  function swapUntilL1_onOutflow(Utils.Context memory ctx, address from, address to) public {
    /*
     * from -> L1[to]
     * This function will do valid swaps until just before L1 is hit
     * during outflow on `to`, therfore we check the negative end
     * of the limit because `to` flows out of the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(to);

    console.log("🏷️ [%d] Swap until L1=%d on outflow", block.timestamp, uint256(limitConfig.limit1));
    int48 maxPerSwap = limitConfig.limit0;

    while (limitState.netflow1 - maxPerSwap >= -1 * limitConfig.limit1) {
      skip(limitConfig.timestep0 + 1);
      // Check that there's still outflow to trade as sometimes we hit LG while
      // still having a bit of L1 left, which causes an infinite loop.
      if (ctx.maxPossibleOutflow(to) == 0) {
        break;
      }
      swapUntilL0_onOutflow(ctx, from, to);
      limitConfig = ctx.tradingLimitsConfig(to);
      limitState = ctx.tradingLimitsState(to);
    }
    skip(limitConfig.timestep0 + 1);
  }

  function swapUntilLG_onOutflow(Utils.Context memory ctx, address from, address to) public {
    /*
     * from -> LG[to]
     * This function will do valid swaps until just before LG is hit
     * during outflow on `to`, therfore we check the negative end
     * of the limit because `to` flows out of the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(to);
    console.log("🏷️ [%d] Swap until LG=%d on outflow", block.timestamp, uint256(limitConfig.limitGlobal));

    if (limitConfig.isLimitEnabled(L1)) {
      int48 maxPerSwap = limitConfig.limit0;
      while (limitState.netflowGlobal - maxPerSwap >= -1 * limitConfig.limitGlobal) {
        skip(limitConfig.timestep1 + 1);
        swapUntilL1_onOutflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(to);
        // Triger an update to reset netflows
        limitState = ctx.tradingLimitsState(to);
      }
      skip(limitConfig.timestep1 + 1);
    } else if (limitConfig.isLimitEnabled(L0)) {
      int48 maxPerSwap = limitConfig.limit0;
      while (limitState.netflowGlobal - maxPerSwap >= -1 * limitConfig.limitGlobal) {
        skip(limitConfig.timestep0 + 1);
        swapUntilL0_onOutflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(to);
        // Triger an update to reset netflows
        limitState = ctx.tradingLimitsState(to);
      }
      skip(limitConfig.timestep0 + 1);
    }
  }

  // ========================= Circuit Breaker Asserts ========================= //

  function assert_breakerBreaks(Utils.Context memory ctx, address breaker, uint256 breakerIndex) public {
    // XXX: There is currently no straightforward way to determine what type of a breaker
    // we are dealing with, so we will use the deployment setup that we currently chose,
    // where the medianDeltaBreaker gets deployed first and the valueDeltaBreaker second.
    bool isMedianDeltaBreaker = breakerIndex == 0;
    bool isValueDeltaBreaker = breakerIndex == 1;
    if (isMedianDeltaBreaker) {
      assert_medianDeltaBreakerBreaks_onIncrease(ctx, breaker);
      assert_medianDeltaBreakerBreaks_onDecrease(ctx, breaker);
    } else if (isValueDeltaBreaker) {
      assert_valueDeltaBreakerBreaks_onIncrease(ctx, breaker);
      assert_valueDeltaBreakerBreaks_onDecrease(ctx, breaker);
    } else {
      revert("Unknown trading mode, can't infer breaker type");
    }
  }

  function assert_medianDeltaBreakerBreaks_onIncrease(Utils.Context memory ctx, address _breaker) public {
    uint256 currentMedian = ensureRateActive(ctx); // ensure trading mode is 0

    // trigger breaker by setting new median to ema - (threshold + 0.001% buffer)
    uint256 currentEMA = MedianDeltaBreaker(_breaker).medianRatesEMA(ctx.getReferenceRateFeedID());
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 thresholdBuffer = FixidityLib.newFixedFraction(1, 1000).unwrap(); // small buffer because of rounding errors
    uint256 maxPercent = fixed1.add(rateChangeThreshold.add(thresholdBuffer));
    uint256 newMedian = currentEMA.mul(maxPercent).div(fixed1);

    console.log("Current Median: ", currentMedian);
    console.log("Current EMA: ", currentEMA);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 3);
  }

  function assert_medianDeltaBreakerBreaks_onDecrease(Utils.Context memory ctx, address _breaker) public {
    uint256 currentMedian = ensureRateActive(ctx); // ensure trading mode is 0

    // trigger breaker by setting new median to ema + (threshold + 0.001% buffer)
    uint256 currentEMA = MedianDeltaBreaker(_breaker).medianRatesEMA(ctx.getReferenceRateFeedID());
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 thresholdBuffer = FixidityLib.newFixedFraction(1, 1000).unwrap(); // small buffer because of rounding errors
    uint256 maxPercent = fixed1.sub(rateChangeThreshold.add(thresholdBuffer));
    uint256 newMedian = currentEMA.mul(maxPercent).div(fixed1);

    console.log("Current Median: ", currentMedian);
    console.log("Current EMA: ", currentEMA);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 3);
  }

  function assert_valueDeltaBreakerBreaks_onIncrease(Utils.Context memory ctx, address _breaker) public {
    uint256 currentMedian = ensureRateActive(ctx); // ensure trading mode is 0

    // trigger breaker by setting new median to reference value + threshold + 1
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 referenceValue = ctx.getValueDeltaBreakerReferenceValue(_breaker);
    uint256 maxPercent = fixed1.add(rateChangeThreshold);
    uint256 newMedian = referenceValue.mul(maxPercent).div(fixed1);
    newMedian = newMedian + 1;

    console.log("Current Median: ", currentMedian);
    console.log("Reference Value: ", referenceValue);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 3);
  }

  function assert_valueDeltaBreakerBreaks_onDecrease(Utils.Context memory ctx, address _breaker) public {
    uint256 currentMedian = ensureRateActive(ctx); // ensure trading mode is 0

    // trigger breaker by setting new median to reference value - threshold - 1
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 referenceValue = ctx.getValueDeltaBreakerReferenceValue(_breaker);
    uint256 maxPercent = fixed1.sub(rateChangeThreshold);
    uint256 newMedian = referenceValue.mul(maxPercent).div(fixed1);
    newMedian = newMedian - 1;

    console.log("Current Median: ", currentMedian);
    console.log("Reference Value: ", referenceValue);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 3);
  }

  function assert_breakerRecovers(Utils.Context memory ctx, address breaker, uint256 breakerIndex) public {
    // XXX: There is currently no straightforward way to determine what type of a breaker
    // we are dealing with, so we will use the deployment setup that we currently chose,
    // where the medianDeltaBreaker gets deployed first and the valueDeltaBreaker second.
    bool isMedianDeltaBreaker = breakerIndex == 0;
    bool isValueDeltaBreaker = breakerIndex == 1;
    if (isMedianDeltaBreaker) {
      assert_medianDeltaBreakerRecovers(ctx, breaker);
    } else if (isValueDeltaBreaker) {
      assert_valueDeltaBreakerRecovers(ctx, breaker);
    } else {
      revert("Unknown trading mode, can't infer breaker type");
    }
  }

  function assert_medianDeltaBreakerRecovers(Utils.Context memory ctx, address _breaker) internal {
    uint256 currentMedian = ensureRateActive(ctx); // ensure trading mode is 0

    // trigger breaker by setting new median to ema + threshold + 0.001%
    uint256 currentEMA = MedianDeltaBreaker(_breaker).medianRatesEMA(ctx.getReferenceRateFeedID());
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 thresholdBuffer = FixidityLib.newFixedFraction(1, 1000).unwrap();
    uint256 maxPercent = fixed1.add(rateChangeThreshold.add(thresholdBuffer));
    uint256 newMedian = currentEMA.mul(maxPercent).div(fixed1);

    console.log("Current Median: ", currentMedian);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 3);

    // wait for cool down and reset by setting new median to ema
    uint256 cooldown = WithCooldown(_breaker).getCooldown(ctx.getReferenceRateFeedID());
    if (cooldown == 0) {
      changePrank(ctx.breakerBox.owner());
      ctx.breakerBox.setRateFeedTradingMode(ctx.getReferenceRateFeedID(), 0);
    } else {
      skip(cooldown);
      currentEMA = MedianDeltaBreaker(_breaker).medianRatesEMA(ctx.getReferenceRateFeedID());
      assert_breakerRecovers_withNewMedian(ctx, currentEMA);
    }
  }

  function assert_valueDeltaBreakerRecovers(Utils.Context memory ctx, address _breaker) internal {
    uint256 currentMedian = ensureRateActive(ctx); // ensure trading mode is 0

    // trigger breaker by setting new median to reference value + threshold + 1
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 referenceValue = ctx.getValueDeltaBreakerReferenceValue(_breaker);
    uint256 maxPercent = fixed1.add(rateChangeThreshold);
    uint256 newMedian = referenceValue.mul(maxPercent).div(fixed1);
    newMedian = newMedian + 1;

    console.log("Current Median: ", currentMedian);
    console.log("Reference Value: ", referenceValue);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 3);

    // wait for cool down and reset by setting new median to refernece value
    uint256 cooldown = WithCooldown(_breaker).getCooldown(ctx.getReferenceRateFeedID());
    if (cooldown == 0) {
      changePrank(ctx.breakerBox.owner());
      ctx.breakerBox.setRateFeedTradingMode(ctx.getReferenceRateFeedID(), 0);
    } else {
      skip(cooldown);
      assert_breakerRecovers_withNewMedian(ctx, referenceValue);
    }
  }

  function assert_breakerBreaks_withNewMedian(
    Utils.Context memory ctx,
    uint256 newMedian,
    uint256 expectedTradingMode
  ) public {
    address rateFeedID = ctx.getReferenceRateFeedID();
    uint256 tradingMode = ctx.breakerBox.getRateFeedTradingMode(rateFeedID);
    require(tradingMode == 0, "breaker should be recovered");

    ctx.updateOracleMedianRate(newMedian);
    tradingMode = ctx.breakerBox.getRateFeedTradingMode(rateFeedID);
    require(tradingMode == expectedTradingMode, "trading more is different from expected");
  }

  function assert_breakerRecovers_withNewMedian(Utils.Context memory ctx, uint256 newMedian) public {
    address rateFeedID = ctx.getReferenceRateFeedID();
    uint256 tradingMode = ctx.breakerBox.getRateFeedTradingMode(rateFeedID);
    require(tradingMode != 0, "breaker should be triggered");

    ctx.updateOracleMedianRate(newMedian);
    tradingMode = ctx.breakerBox.getRateFeedTradingMode(rateFeedID);
    require(tradingMode == 0, "breaker should be recovered");
  }

  function ensureRateActive(Utils.Context memory ctx) internal returns (uint256 newMedian) {
    address rateFeedID = ctx.getReferenceRateFeedID();
    // Always do a small update in order to make sure
    // the breakers are warm.
    (uint256 currentRate, ) = ctx.sortedOracles.medianRate(rateFeedID);
    newMedian = currentRate.add(currentRate.div(100_000_000)); // a small increase
    ctx.updateOracleMedianRate(newMedian);
    uint8 tradingMode = ctx.breakerBox.getRateFeedTradingMode(rateFeedID);
    uint256 attempts = 0;
    while (tradingMode != 0 && attempts < 10) {
      console.log("attempt #%d", attempts);
      attempts++;
      // while the breaker is active, we wait for the cooldown and try to update the median
      console.log(block.timestamp, "Waiting for cooldown to pass");
      console.log("RateFeedID:", rateFeedID);
      address[] memory _breakers = ctx.breakerBox.getBreakers();
      uint256 cooldown = 0;
      uint256 breakerIndex;
      for (uint256 i = 0; i < _breakers.length; i++) {
        if (ctx.breakerBox.isBreakerEnabled(_breakers[i], rateFeedID)) {
          (uint8 _tradingMode, , ) = ctx.breakerBox.rateFeedBreakerStatus(rateFeedID, _breakers[i]);
          if (_tradingMode != 0) {
            breakerIndex = i;
            cooldown = WithCooldown(_breakers[i]).getCooldown(rateFeedID);
            break;
          }
        }
      }
      skip(cooldown);
      newMedian = newMedianToResetBreaker(ctx, breakerIndex);
      ctx.updateOracleMedianRate(newMedian);
      if (cooldown == 0) {
        console.log("Manual recovery required for breaker %s", _breakers[breakerIndex]);
        changePrank(ctx.breakerBox.owner());
        ctx.breakerBox.setRateFeedTradingMode(rateFeedID, 0);
      }
      tradingMode = ctx.breakerBox.getRateFeedTradingMode(rateFeedID);
    }
  }

  function newMedianToResetBreaker(
    Utils.Context memory ctx,
    uint256 breakerIndex
  ) internal view returns (uint256 newMedian) {
    address[] memory _breakers = ctx.breakerBox.getBreakers();
    bool isMedianDeltaBreaker = breakerIndex == 0;
    bool isValueDeltaBreaker = breakerIndex == 1;
    if (isMedianDeltaBreaker) {
      uint256 currentEMA = MedianDeltaBreaker(_breakers[breakerIndex]).medianRatesEMA(ctx.getReferenceRateFeedID());
      return currentEMA;
    } else if (isValueDeltaBreaker) {
      return ctx.getValueDeltaBreakerReferenceValue(_breakers[breakerIndex]);
    } else {
      revert("can't infer corresponding breaker");
    }
  }
}
