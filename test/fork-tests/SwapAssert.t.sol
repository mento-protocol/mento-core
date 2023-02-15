// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test } from "celo-foundry/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { Utils } from "./Utils.t.sol";

import { IERC20Metadata } from "contracts/common/interfaces/IERC20Metadata.sol";
import { TradingLimits } from "contracts/common/TradingLimits.sol";
import { FixidityLib } from "contracts/common/FixidityLib.sol";

contract SwapAssert is Test {
  using Utils for Utils.Context;
  using Utils for TradingLimits.Config;
  using Utils for TradingLimits.State;
  using Utils for uint8;
  using Utils for uint256;
  using TradingLimits for TradingLimits.State;
  using TradingLimits for TradingLimits.Config;
  using FixidityLib for FixidityLib.Fraction;

  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant LG = 4; // 0b100 LimitGlobal

  bool __swapAssertDebug = false;

  uint256 fixed1 = FixidityLib.fixed1().unwrap();
  FixidityLib.Fraction pc10 = FixidityLib.newFixedFraction(10, 100);

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
    ctx.t.mint(from, ctx.t.trader0(), sellAmount);
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
    uint256 maxAmountIn = ctx.broker.getAmountIn(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount);
    ctx.t.mint(from, ctx.t.trader0(), maxAmountIn);
    IERC20Metadata(from).approve(address(ctx.broker), maxAmountIn);
    vm.expectRevert(bytes(revertReason));
    ctx.broker.swapOut(ctx.exchangeProvider, ctx.exchangeId, from, to, buyAmount, maxAmountIn);
  }

  function assert_swapOverLimitFails(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) internal {
    TradingLimits.Config memory limitConfigFrom = ctx.tradingLimitsConfig(from);
    TradingLimits.Config memory limitConfigTo = ctx.tradingLimitsConfig(to);

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

    uint256 outflowRequiredUnits = uint256(limitConfig.getLimit(limit) + limitState.getNetflow(limit)) + 2;
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
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(from);

    console.log(block.timestamp, "Swap until limit on from (L0)");
    int48 maxPossible = limitConfig.limit0 - limitState.netflow0;
    console.log("Max possible: ");
    console.logInt(maxPossible);
    if (maxPossible > 0) {
      ctx.swapIn(from, to, uint256(maxPossible).toSubunits(from));
    }
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
    console.log(block.timestamp, "Swap until limit on from (L1)");
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
    console.log(block.timestamp, "Swap until limit on from (LG)");

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
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);

    console.log(block.timestamp, "Swap until limit on to (L0)");
    int48 maxPossible = limitConfig.limit0 + limitState.netflow0 - 1;
    console.log("Max possible: ");
    console.logInt(maxPossible);
    if (maxPossible > 0) {
      ctx.swapOut(from, to, uint256(maxPossible).toSubunits(to));
    }
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
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);

    console.log(block.timestamp, "Swap until limit on to (L1)");
    int48 maxPerSwap = limitConfig.limit0 - 1;

    while (limitState.netflow1 - maxPerSwap > -1 * limitConfig.limit1) {
      skip(limitConfig.timestep0 + 1);
      swapUntilL0_onOutflow(ctx, from, to);
      limitConfig = ctx.tradingLimitsConfig(to);
      limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);
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
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);

    console.log(block.timestamp, "Swap until limit on to (LG)");

    if (limitConfig.isLimitEnabled(L1)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal - maxPerSwap > -1 * limitConfig.limitGlobal) {
        skip(limitConfig.timestep1 + 1);
        swapUntilL1_onOutflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(to);
        // Triger an update to reset netflows
        limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);
      }
      skip(limitConfig.timestep1 + 1);
    } else if (limitConfig.isLimitEnabled(L0)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal - maxPerSwap > -1 * limitConfig.limitGlobal) {
        skip(limitConfig.timestep0 + 1);
        swapUntilL0_onOutflow(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(to);
        // Triger an update to reset netflows
        limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);
      }
      skip(limitConfig.timestep0 + 1);
    }
  }
}
