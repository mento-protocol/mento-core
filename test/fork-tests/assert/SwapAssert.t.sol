// SPDX-License-Identifier: UNLICENSED
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

import { Test } from "celo-foundry/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { console } from "forge-std/console.sol";
import { Utils } from "../Utils.t.sol";

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

  function assert_swap(
    Utils.Context memory ctx,
    address from,
    address to,
    uint256 sellAmount
  ) internal {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);
    uint256 amountOut = ctx.swap(from, to, sellAmount);
    uint256 expectedAmountOut = FixidityLib.newFixed(sellAmount).divide(rate).unwrap() / fixed1;
    assertApproxEqAbs(
      amountOut,
      expectedAmountOut,
      pc10.multiply(FixidityLib.newFixed(expectedAmountOut)).unwrap() / fixed1
    );
  }

  function assert_swapFails(
    Utils.Context memory ctx,
    address from,
    address to,
    uint256 sellAmount,
    string memory revertReason
  ) internal {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);
    ctx.t.mint(from, ctx.t.trader0(), sellAmount);
    IERC20Metadata(from).approve(address(ctx.broker), sellAmount);

    uint256 minAmountOut = ctx.broker.getAmountOut(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount); // slippage
    vm.expectRevert(bytes(revertReason));
    uint256 amountOut = ctx.broker.swapIn(ctx.exchangeProvider, ctx.exchangeId, from, to, sellAmount, minAmountOut);
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
      assert_swapOverLimitFails_onFrom(ctx, from, to, limit);
    } else if (limitConfigTo.isLimitEnabled(limit)) {
      assert_swapOverLimitFails_onTo(ctx, from, to, limit);
    }
  }

  function assert_swapOverLimitFails_onFrom(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) internal {
    // L[from] -> to, `from` flows into the reserve, so limit tested on positive end

    // This should do valid swaps until just before the limit is reached
    swapUntilLimit_onFrom(ctx, from, to, limit);
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(from);

    uint256 inflowRequiredUnits = uint256(limitConfig.getLimit(limit) - limitState.getNetflow(limit)) + 1;
    console.log("Inflow required: ", inflowRequiredUnits);
    assert_swapFails(ctx, from, to, inflowRequiredUnits.toSubunits(from), limit.revertReason());
  }

  function swapUntilLimit_onFrom(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) public {
    if (limit == L0) {
      swapUntilLimit0_onFrom(ctx, from, to);
    } else if (limit == L1) {
      swapUntilLimit1_onFrom(ctx, from, to);
    } else if (limit == LG) {
      swapUntilLimitGlobal_onFrom(ctx, from, to);
    } else {
      revert("Invalid limit");
    }
  }

  function swapUntilLimit0_onFrom(
    Utils.Context memory ctx,
    address from,
    address to
  ) internal {
    // L[from] -> to, `from` flows into the reserve, so limit tested on positive end
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(from).update(limitConfig, 0, 0);

    console.log(block.timestamp, "Swap until limit on from (L0)");
    int48 maxPossible = limitConfig.limit0 - limitState.netflow0;
    console.log("Max possible: ");
    console.logInt(maxPossible);
    if (maxPossible > 0) {
      ctx.swap(from, to, uint256(maxPossible).toSubunits(from));
    }
  }

  function swapUntilLimit1_onFrom(
    Utils.Context memory ctx,
    address from,
    address to
  ) internal {
    // L[from] -> to, `from` flows into the reserve, so limit tested on positive end
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(from).update(limitConfig, 0, 0);
    console.log(block.timestamp, "Swap until limit on from (L1)");
    int48 maxPerSwap = limitConfig.limit0 - 1;

    while (limitState.netflow1 + maxPerSwap < limitConfig.limit1) {
      skip(limitConfig.timestep0 + 1);
      swapUntilLimit0_onFrom(ctx, from, to);
      limitConfig = ctx.tradingLimitsConfig(from);
      // Triger an update to reset netflows 
      limitState = ctx.tradingLimitsState(from).update(limitConfig, 0, 0);
    }
    skip(limitConfig.timestep0 + 1);
  }

  function swapUntilLimitGlobal_onFrom(
    Utils.Context memory ctx,
    address from,
    address to
  ) internal {
    // L[from] -> to, `from` flows into the reserve, so limit tested on positive end
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(from);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(from).update(limitConfig, 0, 0);
    console.log(block.timestamp, "Swap until limit on from (LG)");

    if (limitConfig.isLimitEnabled(L1)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal + maxPerSwap < limitConfig.limitGlobal) {
        skip(limitConfig.timestep1 + 1);
        swapUntilLimit1_onFrom(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(from);
        // Triger an update to reset netflows 
        limitState = ctx.tradingLimitsState(from).update(limitConfig, 0, 0);
      }
      skip(limitConfig.timestep1 + 1);
    } else if (limitConfig.isLimitEnabled(L0)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal + maxPerSwap < limitConfig.limitGlobal) {
        skip(limitConfig.timestep0 + 1);
        swapUntilLimit0_onFrom(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(from);
        // Triger an update to reset netflows 
        limitState = ctx.tradingLimitsState(from).update(limitConfig, 0, 0);
      }
      skip(limitConfig.timestep0 + 1);
    }
  }

  function assert_swapOverLimitFails_onTo(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) internal {
    // from -> L[to], `to` flows out of the reserve, so limit tested on the negative end

    // This should do valid swaps until just before the limit is reached
    swapUntilLimit_onTo(ctx, from, to, limit);
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to);

    uint256 outflowRequiredUnits = uint256(limitConfig.getLimit(limit) + limitState.getNetflow(limit)) + 2;
    console.log("Outflow required: ", outflowRequiredUnits);
    uint256 amountIn =
      ctx.broker.getAmountIn(
        ctx.exchangeProvider,
        ctx.exchangeId,
        from,
        to,
        outflowRequiredUnits.toSubunits(to)
      );
    assert_swapFails(ctx, from, to, amountIn, limit.revertReason());
  }

  function swapUntilLimit_onTo(
    Utils.Context memory ctx,
    address from,
    address to,
    uint8 limit
  ) public {
    if (limit == L0) {
      swapUntilLimit0_onTo(ctx, from, to);
    } else if (limit == L1) {
      swapUntilLimit1_onTo(ctx, from, to);
    } else if (limit == LG) {
      swapUntilLimitGlobal_onTo(ctx, from, to);
    } else {
      revert("Invalid limit");
    }
  } 

  function swapUntilLimit0_onTo(
    Utils.Context memory ctx,
    address from,
    address to
  ) public {
    // from -> L[to], `to` flows out of the reserve, so limit tested on the negative end
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);

    console.log(block.timestamp, "Swap until limit on to (L0)");
    console.logInt(limitConfig.limit0);
    console.logInt(limitState.netflow0);
    int48 maxPossible = limitConfig.limit0 + limitState.netflow0;
    console.log("Max possible: ");
    console.logInt(maxPossible);
    if (maxPossible > 0) {
      uint256 amountIn =
        ctx.broker.getAmountIn(
          ctx.exchangeProvider,
          ctx.exchangeId,
          from,
          to,
          uint256(maxPossible).toSubunits(to)
        );
      ctx.swap(from, to, amountIn);
    }
  }

  function swapUntilLimit1_onTo(
    Utils.Context memory ctx,
    address from,
    address to
  ) public {
    // from -> L[to], `to` flows out of the reserve, so limit tested on the negative end
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);

    console.log(block.timestamp, "Swap until limit on to (L1)");
    int48 maxPerSwap = limitConfig.limit0 - 1;

    while (limitState.netflow1 - maxPerSwap > -1 * limitConfig.limit1) {
      skip(limitConfig.timestep0 + 1);
      swapUntilLimit0_onFrom(ctx, from, to);
      limitConfig = ctx.tradingLimitsConfig(to);
      limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);
    }
    skip(limitConfig.timestep0 + 1);
  }

  function swapUntilLimitGlobal_onTo(
    Utils.Context memory ctx,
    address from,
    address to
  ) public {
    // from -> L[to], `to` flows out of the reserve, so limit tested on the negative end
    TradingLimits.Config memory limitConfig = ctx.tradingLimitsConfig(to);
    TradingLimits.State memory limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);

    console.log(block.timestamp, "Swap until limit on to (LG)");

    if (limitConfig.isLimitEnabled(L1)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal - maxPerSwap > -1 * limitConfig.limitGlobal) {
        skip(limitConfig.timestep1 + 1);
        swapUntilLimit1_onFrom(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(to);
        // Triger an update to reset netflows 
        limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);
      }
      skip(limitConfig.timestep1 + 1);
    } else if (limitConfig.isLimitEnabled(L0)) {
      int48 maxPerSwap = limitConfig.limit0 - 1;
      while (limitState.netflowGlobal - maxPerSwap > -1 * limitConfig.limitGlobal) {
        skip(limitConfig.timestep0 + 1);
        swapUntilLimit0_onFrom(ctx, from, to);
        limitConfig = ctx.tradingLimitsConfig(to);
        // Triger an update to reset netflows 
        limitState = ctx.tradingLimitsState(to).update(limitConfig, 0, 0);
      }
      skip(limitConfig.timestep0 + 1);
    }
  }
}
