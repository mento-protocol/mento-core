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
import { TradingLimits } from "contracts/common/TradingLimits.sol";
import { WithCooldown } from "contracts/common/breakers/WithCooldown.sol";
import { IBreaker } from "contracts/interfaces/IBreaker.sol";
import { MedianDeltaBreaker } from "contracts/MedianDeltaBreaker.sol";
import { ValueDeltaBreaker } from "contracts/ValueDeltaBreaker.sol";

contract TestAsserts is Test {
  using Utils for Utils.Context;
  using Utils for TradingLimits.Config;
  using Utils for TradingLimits.State;
  using Utils for uint8;
  using Utils for uint256;
  using SafeMath for uint256;
  using TradingLimits for TradingLimits.State;
  using TradingLimits for TradingLimits.Config;
  using FixidityLib for FixidityLib.Fraction;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  uint256 fixed1 = FixidityLib.fixed1().unwrap();
  FixidityLib.Fraction pc10 = FixidityLib.newFixedFraction(10, 100);

  // ========================= Swap Asserts ========================= //

  function assert_swapIn(
    Utils.Context memory ctx,
    address from,
    address to,
    uint256 sellAmount
  ) internal {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);
    uint256 amountOut = ctx.swapIn(from, to, sellAmount);
    uint256 expectedAmountOut = FixidityLib.newFixed(sellAmount).divide(rate).unwrap() / fixed1;
    assertApproxEqAbs(
      amountOut,
      expectedAmountOut,
      pc10.multiply(FixidityLib.newFixed(expectedAmountOut)).unwrap() / fixed1
    );
  }

  function assert_swapOut(
    Utils.Context memory ctx,
    address from,
    address to,
    uint256 buyAmount
  ) internal {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);
    uint256 amountIn = ctx.swapOut(from, to, buyAmount);
    uint256 expectedAmountIn = FixidityLib.newFixed(buyAmount).multiply(rate).unwrap() / fixed1;
    assertApproxEqAbs(
      amountIn,
      expectedAmountIn,
      pc10.multiply(FixidityLib.newFixed(expectedAmountIn)).unwrap() / fixed1
    );
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

  function assert_swapOverLimitFails(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) internal {
    TradingLimits.Config memory limitConfigFrom = ctx.tradingLimitsConfig(from);
    TradingLimits.Config memory limitConfigTo = ctx.tradingLimitsConfig(to);
    console.log(
      string(abi.encodePacked(
        "Swapping ", 
        IERC20Metadata(from).symbol(), 
        " -> ", 
        IERC20Metadata(to).symbol()
      )),
      "with limit", 
      limit.limitString()
    );
    console.log("========================================");


    // Always only one limit on a pair
    if (limitConfigFrom.isLimitEnabled(limit)) {
      assert_swapOverLimitFails_onInflow(ctx, from, to, limit);
    } else if (limitConfigTo.isLimitEnabled(limit)) {
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

  function swapUntilL0_onInflow(
    Utils.Context memory ctx,
    address from,
    address to
  ) internal {
    /*
     * L0[from] -> to
     * This function will do valid swaps until just before L0 is hit
     * during inflow on `from`, therfore we check the positive end
     * of the limit because `from` flows into the reserve.
     */

    console.log("🏷️[",block.timestamp, "] Swap until L0 on inflow");
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
  }

  function swapUntilL1_onInflow(
    Utils.Context memory ctx,
    address from,
    address to
  ) internal {
    /*
     * L1[from] -> to
     * This function will do valid swaps until just before L1 is hit
     * during inflow on `from`, therfore we check the positive end
     * of the limit because `from` flows into the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(from);
    console.log("🏷️[",block.timestamp, "] Swap until L1 on inflow");
    int48 maxPerSwap = limitConfig.limit0 - 1;

    while (limitState.netflow1 + maxPerSwap < limitConfig.limit1) {
      skip(limitConfig.timestep0 + 1);
      swapUntilL0_onInflow(ctx, from, to);
      limitConfig = ctx.tradingLimitsConfig(from);
      limitState = ctx.tradingLimitsState(from);
    }
    skip(limitConfig.timestep0 + 1);
  }

  function swapUntilLG_onInflow(
    Utils.Context memory ctx,
    address from,
    address to
  ) internal {
    /*
     * L1[from] -> to
     * This function will do valid swaps until just before LG is hit
     * during inflow on `from`, therfore we check the positive end
     * of the limit because `from` flows into the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(from);
    console.log("🏷️[",block.timestamp, "] Swap until LG on inflow");

    if (limitConfig.isLimitEnabled(L1)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal + maxPerSwap < limitConfig.limitGlobal) {
        skip(limitConfig.timestep1 + 1);
        swapUntilL1_onInflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(from);
        limitState = ctx.tradingLimitsState(from);
      }
      skip(limitConfig.timestep1 + 1);
    } else if (limitConfig.isLimitEnabled(L0)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal + maxPerSwap < limitConfig.limitGlobal) {
        skip(limitConfig.timestep0 + 1);
        swapUntilL0_onInflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(from);
        limitState = ctx.tradingLimitsState(from);
      }
      skip(limitConfig.timestep0 + 1);
    }
  }

  function swapUntilL0_onOutflow(
    Utils.Context memory ctx,
    address from,
    address to
  ) public {
    /*
     * from -> L0[to]
     * This function will do valid swaps until just before L0 is hit
     * during outflow on `to`, therfore we check the negative end
     * of the limit because `to` flows out of the reserve.
     */

    console.log("🏷️[",block.timestamp, "] Swap until L0 on outflow");
    uint256 maxPossible;
    uint256 maxPossibleUntilLimit;
    do {
      int48 maxPossibleUntilLimitUnits = ctx.maxPossibleOutflow(to);
      require(maxPossibleUntilLimitUnits >= 0, "max possible trade amount is negative");
      maxPossibleUntilLimit = uint256(maxPossibleUntilLimitUnits).toSubunits(to);
      maxPossible = ctx.maxSwapOut(maxPossibleUntilLimit, from, to);

      if (maxPossible > 0) {
        ctx.swapOut(from, to, maxPossible);
      }
    } while (maxPossible > 0 && maxPossibleUntilLimit > maxPossible);
  }

  function swapUntilL1_onOutflow(
    Utils.Context memory ctx,
    address from,
    address to
  ) public {
    /*
     * from -> L1[to]
     * This function will do valid swaps until just before L1 is hit
     * during outflow on `to`, therfore we check the negative end
     * of the limit because `to` flows out of the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(to);

    console.log("🏷️[",block.timestamp, "] Swap until L1 on outflow");
    int48 maxPerSwap = limitConfig.limit0 - 1;

    while (limitState.netflow1 - maxPerSwap > -1 * limitConfig.limit1) {
      skip(limitConfig.timestep0 + 1);
      swapUntilL0_onOutflow(ctx, from, to);
      limitConfig = ctx.tradingLimitsConfig(to);
      limitState = ctx.tradingLimitsState(to);
    }
    skip(limitConfig.timestep0 + 1);
  }

  function swapUntilLG_onOutflow(
    Utils.Context memory ctx,
    address from,
    address to
  ) public {
    /*
     * from -> LG[to]
     * This function will do valid swaps until just before LG is hit
     * during outflow on `to`, therfore we check the negative end
     * of the limit because `to` flows out of the reserve.
     */
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(to);
    console.log("🏷️[",block.timestamp, "] Swap until LG on outflow");

    if (limitConfig.isLimitEnabled(L1)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal - maxPerSwap > -1 * limitConfig.limitGlobal) {
        skip(limitConfig.timestep1 + 1);
        swapUntilL1_onOutflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(to);
        // Triger an update to reset netflows
        limitState = ctx.tradingLimitsState(to);
      }
      skip(limitConfig.timestep1 + 1);
    } else if (limitConfig.isLimitEnabled(L0)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal - maxPerSwap > -1 * limitConfig.limitGlobal) {
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

  function assert_breakerBreaks(
    Utils.Context memory ctx,
    address breaker,
    uint256 tradingMode
  ) public {
    // XXX: There is currently no straightforward way to determine what type of a breaker
    // we are dealing with, so we will use the deployment setup that we currently chose,
    // MedianDeltaBreaker => tradingMode == 1
    // ValueDeltaBreaker => tradingMode == 2
    if (tradingMode == 1) {
      assert_medianDeltaBreakerBreaks_onIncrease(ctx, breaker);
      assert_medianDeltaBreakerBreaks_onDecrease(ctx, breaker);
    } else if (tradingMode == 2) {
      assert_valueDeltaBreakerBreaks_onIncrease(ctx, breaker);
      assert_valueDeltaBreakerBreaks_onDecrease(ctx, breaker);
    } else {
      revert("Unknown trading mode, can't infer breaker type");
    }
  }

  function assert_medianDeltaBreakerBreaks_onIncrease(Utils.Context memory ctx, address _breaker) public {
    console.log("MedianDeltaBreaker breaks on price increase");
    uint256 currentMedian = ensureRateActive(ctx);
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);

    uint256 maxPercent = fixed1.add(rateChangeThreshold);
    uint256 newMedian = currentMedian.mul(maxPercent).div(fixed1);
    newMedian = newMedian + 1;
    console.log("Current Median: ", currentMedian);
    console.log("New Median: ", newMedian);

    assert_breakerBreaks_withNewMedian(ctx, newMedian, 1);
  }

  function assert_medianDeltaBreakerBreaks_onDecrease(Utils.Context memory ctx, address _breaker) public {
    console.log("MedianDeltaBreaker breaks on price decrease");
    uint256 currentMedian = ensureRateActive(ctx);
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);

    uint256 maxPercent = fixed1.sub(rateChangeThreshold);
    uint256 newMedian = currentMedian.mul(maxPercent).div(fixed1);
    newMedian = newMedian - 1;
    console.log("Current Median: ", currentMedian);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 1);
  }

  function assert_valueDeltaBreakerBreaks_onIncrease(Utils.Context memory ctx, address _breaker) public {
    console.log("ValueDeltaBreaker breaks on price increase");
    uint256 currentMedian = ensureRateActive(ctx);
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 referenceValue = ctx.getValueDeltaBreakerReferenceValue(_breaker);

    uint256 maxPercent = fixed1.add(rateChangeThreshold);
    uint256 newMedian = referenceValue.mul(maxPercent).div(fixed1);
    newMedian = newMedian + 1;

    console.log("Current Median: ", currentMedian);
    console.log("Reference Value: ", referenceValue);
    console.log("New Median: ", newMedian);

    assert_breakerBreaks_withNewMedian(ctx, newMedian, 2);
  }

  function assert_valueDeltaBreakerBreaks_onDecrease(Utils.Context memory ctx, address _breaker) public {
    console.log("ValueDeltaBreaker breaks on price decrease");
    uint256 currentMedian = ensureRateActive(ctx);
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 referenceValue = ctx.getValueDeltaBreakerReferenceValue(_breaker);

    uint256 maxPercent = fixed1.sub(rateChangeThreshold);
    uint256 newMedian = referenceValue.mul(maxPercent).div(fixed1);
    newMedian = newMedian - 1;
    console.log("Current Median: ", currentMedian);
    console.log("Reference Value: ", referenceValue);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 2);
  }

  function assert_breakerRecovers(
    Utils.Context memory ctx,
    address breaker,
    uint256 tradingMode
  ) public {
    // XXX: There is currently no straightforward way to determine what type of a breaker
    // we are dealing with, so we will use the deployment setup that we currently chose,
    // MedianDeltaBreaker => tradingMode == 1
    // ValueDeltaBreaker => tradingMode == 2
    if (tradingMode == 1) {
      assert_medianDeltaBreakerRecovers(ctx, breaker);
    } else if (tradingMode == 2) {
      assert_valueDeltaBreakerRecovers(ctx, breaker);
    } else {
      revert("Unknown trading mode, can't infer breaker type");
    }
  }

  function assert_medianDeltaBreakerRecovers(Utils.Context memory ctx, address _breaker) internal {
    console.log("MedianDeltaBreaker recovers");
    uint256 currentMedian = ensureRateActive(ctx);
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);

    uint256 maxPercent = fixed1.add(rateChangeThreshold);
    uint256 newMedian = currentMedian.mul(maxPercent).div(fixed1);
    newMedian = newMedian + 1;
    console.log("Current Median: ", currentMedian);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 1);

    uint256 cooldown = WithCooldown(_breaker).getCooldown(ctx.getReferenceRateFeedID());
    skip(cooldown);
    assert_breakerRecovers_withNewMedian(ctx, newMedian.add(newMedian.div(1000)));
  }

  function assert_valueDeltaBreakerRecovers(Utils.Context memory ctx, address _breaker) internal {
    console.log("ValueDeltaBreaker recovers");
    uint256 currentMedian = ensureRateActive(ctx);
    uint256 rateChangeThreshold = ctx.getBreakerRateChangeThreshold(_breaker);
    uint256 referenceValue = ctx.getValueDeltaBreakerReferenceValue(_breaker);

    uint256 maxPercent = fixed1.add(rateChangeThreshold);
    uint256 newMedian = referenceValue.mul(maxPercent).div(fixed1);
    newMedian = newMedian + 1;
    console.log("Current Median: ", currentMedian);
    console.log("Reference Value: ", referenceValue);
    console.log("New Median: ", newMedian);
    assert_breakerBreaks_withNewMedian(ctx, newMedian, 2);

    uint256 cooldown = WithCooldown(_breaker).getCooldown(ctx.getReferenceRateFeedID());
    skip(cooldown);
    assert_breakerRecovers_withNewMedian(ctx, referenceValue);
  }

  function assert_breakerBreaks_withNewMedian(
    Utils.Context memory ctx,
    uint256 newMedian,
    uint256 expectedTradingMode
  ) public {
    address rateFeedID = ctx.getReferenceRateFeedID();
    (uint256 tradingMode, , ) = ctx.breakerBox.rateFeedTradingModes(rateFeedID);
    require(tradingMode == 0, "breaker should be recovered");

    ctx.updateOracleMedianRate(newMedian);
    (tradingMode, , ) = ctx.breakerBox.rateFeedTradingModes(rateFeedID);
    require(tradingMode == expectedTradingMode, "trading more is different from expected");
  }

  function assert_breakerRecovers_withNewMedian(Utils.Context memory ctx, uint256 newMedian) public {
    address rateFeedID = ctx.getReferenceRateFeedID();
    (uint256 tradingMode, , ) = ctx.breakerBox.rateFeedTradingModes(rateFeedID);
    require(tradingMode != 0, "breaker should be triggered");

    ctx.updateOracleMedianRate(newMedian);
    (tradingMode, , ) = ctx.breakerBox.rateFeedTradingModes(rateFeedID);
    require(tradingMode == 0, "breaker should be recovered");
  }

  function ensureRateActive(Utils.Context memory ctx) internal returns (uint256 newMedian) {
    address rateFeedID = ctx.getReferenceRateFeedID();
    // Always do a small update in order to make sure
    // the breakers are warm.
    (uint256 currentRate, ) = ctx.sortedOracles.medianRate(rateFeedID);
    newMedian = currentRate.add(currentRate.div(1000)); // +0.1%
    ctx.updateOracleMedianRate(newMedian);

    (uint64 tradingMode, , ) = ctx.breakerBox.rateFeedTradingModes(rateFeedID);
    while (tradingMode != 0) {
      // while the breaker is active, we wait for the cooldown and try to update the median
      console.log(block.timestamp, "Waiting for cooldown to pass");
      console.log("RateFeedID:", rateFeedID);
      address breaker = ctx.breakerBox.tradingModeBreaker(tradingMode);
      uint256 cooldown = WithCooldown(breaker).getCooldown(rateFeedID);
      skip(cooldown);
      newMedian = newMedianToResetBreaker(ctx, tradingMode);
      ctx.updateOracleMedianRate(newMedian);
      (tradingMode, , ) = ctx.breakerBox.rateFeedTradingModes(rateFeedID);
    }
  }

  function newMedianToResetBreaker(
    Utils.Context memory ctx,
    uint64 tradingMode
  ) internal view returns (uint256 newMedian) {
    address rateFeedID = ctx.getReferenceRateFeedID();
    address breaker = ctx.breakerBox.tradingModeBreaker(tradingMode);
    if (tradingMode == 1) {
      (uint256 currentRate,) = ctx.sortedOracles.medianRate(rateFeedID);
      return currentRate.add(currentRate.div(1000)); // +0.1%
    } else if (tradingMode == 2) {
      return ctx.getValueDeltaBreakerReferenceValue(breaker);
    } else {
      revert("Unknown trading mode, can't infer breaker type");
    }
  }
}
