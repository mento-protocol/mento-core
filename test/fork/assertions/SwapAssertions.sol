// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { console } from "forge-std/console.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { ExchangeForkTest } from "../ExchangeForkTest.sol";
import { Actions } from "../actions/all.sol";
import { TokenHelpers } from "../helpers/TokenHelpers.sol";
import { OracleHelpers } from "../helpers/OracleHelpers.sol";
import { SwapHelpers } from "../helpers/SwapHelpers.sol";
import { TradingLimitHelpers } from "../helpers/TradingLimitHelpers.sol";
import { LogHelpers } from "../helpers/LogHelpers.sol";
import { L0, L1, LG } from "../helpers/misc.sol";

contract SwapAssertions is StdAssertions, Actions {
  using FixidityLib for FixidityLib.Fraction;
  using OracleHelpers for *;
  using SwapHelpers for *;
  using TokenHelpers for *;
  using TradingLimitHelpers for *;
  using LogHelpers for *;

  uint256 fixed1 = FixidityLib.fixed1().unwrap();
  FixidityLib.Fraction pc10 = FixidityLib.newFixedFraction(10, 100);

  function assert_swapIn(address from, address to) internal {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);

    uint256 sellAmount;
    uint256 oneFromAsTo = FixidityLib.wrap(1e24).divide(rate).unwrap();
    uint256 oneToAsFrom = FixidityLib.wrap(1e24).multiply(rate).unwrap();
    if (oneFromAsTo < 1e24) {
      uint256 sellAmountUnits = ((oneToAsFrom / 1e24) * 110) / 100;
      sellAmount = sellAmountUnits.toSubunits(from);
    } else {
      sellAmount = uint256(1).toSubunits(from);
    }

    FixidityLib.Fraction memory amountIn = sellAmount.toUnitsFixed(from);
    FixidityLib.Fraction memory amountOut = swapIn(from, to, sellAmount).toUnitsFixed(to);
    FixidityLib.Fraction memory expectedAmountOut = amountIn.divide(rate);

    assertApproxEqAbs(amountOut.unwrap(), expectedAmountOut.unwrap(), pc10.multiply(expectedAmountOut).unwrap());
  }

  function assert_swapInFails(
    ExchangeForkTest ctx,
    address from,
    address to,
    uint256 sellAmount,
    string memory revertReason
  ) internal {
    ctx.addReportsIfNeeded();
    ctx.mint(from, ctx.trader(), sellAmount, true);
    _vm.startPrank(ctx.trader());
    IERC20(from).approve(address(ctx.broker()), sellAmount);
    uint256 minAmountOut = ctx.broker().getAmountOut(
      ctx.exchangeProviderAddr(),
      ctx.exchangeId(),
      from,
      to,
      sellAmount
    );
    _vm.expectRevert(bytes(revertReason));
    ctx._swapIn(from, to, sellAmount, minAmountOut);
    _vm.stopPrank();
  }

  function assert_swapOutFails(
    ExchangeForkTest ctx,
    address from,
    address to,
    uint256 buyAmount,
    string memory revertReason
  ) internal {
    ctx.addReportsIfNeeded();
    uint256 maxAmountIn = ctx.broker().getAmountIn(ctx.exchangeProviderAddr(), ctx.exchangeId(), from, to, buyAmount);
    ctx.mint(from, ctx.trader(), maxAmountIn, true);
    _vm.startPrank(ctx.trader());
    IERC20(from).approve(address(ctx.broker()), maxAmountIn);
    _vm.expectRevert(bytes(revertReason));
    ctx._swapOut(from, to, buyAmount, maxAmountIn);
    _vm.stopPrank();
  }

  function assert_swapOverLimitFails(ExchangeForkTest ctx, address from, address to, uint8 limit) internal {
    ITradingLimits.Config memory fromLimitConfig = ctx.tradingLimitsConfig(from);
    ITradingLimits.Config memory toLimitConfig = ctx.tradingLimitsConfig(to);
    console.log(
      string(abi.encodePacked("Swapping ", from.symbol(), " -> ", to.symbol())),
      "with limit",
      limit.toString()
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

  function assert_swapOverLimitFails_onInflow(ExchangeForkTest ctx, address from, address to, uint8 limit) internal {
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

    ITradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    ITradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(from);

    uint256 inflowRequiredUnits = uint256(int256(limitConfig.getLimit(limit)) - limitState.getNetflow(limit)) + 1;
    console.log("Inflow required to pass limit: %d", inflowRequiredUnits);
    if (limit != LG && ctx.atInflowLimit(from, LG)) {
      console.log(unicode"🚨 Cannot validate limit %s as LG is already reached.", limit.toString());
    } else {
      assert_swapInFails(ctx, from, to, inflowRequiredUnits.toSubunits(from), limit.revertReason());
    }
  }

  function assert_swapOverLimitFails_onOutflow(ExchangeForkTest ctx, address from, address to, uint8 limit) internal {
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

    ITradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    ITradingLimits.State memory limitState = ctx.refreshedTradingLimitsState(to);

    uint256 outflowRequiredUnits = uint256(int256(limitConfig.getLimit(limit)) + limitState.getNetflow(limit)) + 1;
    console.log("Outflow required: ", outflowRequiredUnits);
    if (limit != LG && ctx.atOutflowLimit(from, LG)) {
      console.log(unicode"🚨 Cannot validate limit %s as LG is already reached.", limit.toString());
    } else {
      assert_swapOutFails(ctx, from, to, outflowRequiredUnits.toSubunits(to), limit.revertReason());
    }
  }
}
