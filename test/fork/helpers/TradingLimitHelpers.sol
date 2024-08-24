// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

import { ITradingLimits } from "contracts/interfaces/ITradingLimits.sol";

import { ExchangeForkTest } from "../ExchangeForkTest.sol";
import { OracleHelpers } from "./OracleHelpers.sol";
import { L0, L1, LG, min } from "./misc.sol";

library TradingLimitHelpers {
  using FixidityLib for FixidityLib.Fraction;
  using OracleHelpers for *;

  function isLimitConfigured(ExchangeForkTest ctx, bytes32 limitId) public view returns (bool) {
    ITradingLimits.Config memory limitConfig = ctx.broker().tradingLimitsConfig(limitId);
    return limitConfig.flags > uint8(0);
  }

  function tradingLimitsConfig(
    ExchangeForkTest ctx,
    bytes32 limitId
  ) public view returns (ITradingLimits.Config memory) {
    return ctx.broker().tradingLimitsConfig(limitId);
  }

  function tradingLimitsState(ExchangeForkTest ctx, bytes32 limitId) public view returns (ITradingLimits.State memory) {
    return ctx.broker().tradingLimitsState(limitId);
  }

  function tradingLimitsConfig(ExchangeForkTest ctx, address asset) public view returns (ITradingLimits.Config memory) {
    bytes32 assetBytes32 = bytes32(uint256(uint160(asset)));
    return ctx.broker().tradingLimitsConfig(ctx.exchangeId() ^ assetBytes32);
  }

  function tradingLimitsState(ExchangeForkTest ctx, address asset) public view returns (ITradingLimits.State memory) {
    bytes32 assetBytes32 = bytes32(uint256(uint160(asset)));
    return ctx.broker().tradingLimitsState(ctx.exchangeId() ^ assetBytes32);
  }

  function refreshedTradingLimitsState(
    ExchangeForkTest ctx,
    address asset
  ) public view returns (ITradingLimits.State memory state) {
    ITradingLimits.Config memory config = tradingLimitsConfig(ctx, asset);
    // Netflow might be outdated because of a skip(...) call and doing
    // an update(0) would reset the netflow if enough time has passed.
    state = ctx.tradingLimits().update(tradingLimitsState(ctx, asset), config, 0, 0);
    // XXX: There's a bug in our current TradingLimits library implementation where
    // an update with 0 netflow will round to 1. So we do another update with -1 netflow
    // to get it back to the actual value.
    state = ctx.tradingLimits().update(state, config, -1, 0);
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

  function toString(uint8 limit) internal pure returns (string memory) {
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

  function atInflowLimit(ExchangeForkTest ctx, address asset, uint8 limit) internal view returns (bool) {
    ITradingLimits.Config memory limitConfig = tradingLimitsConfig(ctx, asset);
    ITradingLimits.State memory limitState = refreshedTradingLimitsState(ctx, asset);
    int256 netflow = getNetflow(limitState, limit);
    int256 limitValue = int256(getLimit(limitConfig, limit));
    // if (netflow > 0) return false;
    return netflow >= limitValue;
  }

  function atOutflowLimit(ExchangeForkTest ctx, address asset, uint8 limit) internal view returns (bool) {
    ITradingLimits.Config memory limitConfig = tradingLimitsConfig(ctx, asset);
    ITradingLimits.State memory limitState = refreshedTradingLimitsState(ctx, asset);
    if (limitConfig.flags & limit == 0) return false;
    int256 netflow = getNetflow(limitState, limit);
    int256 limitValue = int256(getLimit(limitConfig, limit));
    // if (netflow < 0) return false;
    return netflow <= -1 * limitValue;
  }

  function maxInflow(ExchangeForkTest ctx, address from, address to) internal view returns (int48) {
    FixidityLib.Fraction memory rate = ctx.getReferenceRateFraction(from);
    int48 inflow = maxInflow(ctx, from);
    int48 outflow = maxOutflow(ctx, to);
    int48 outflowAsInflow = int48(
      uint48(FixidityLib.multiply(rate, FixidityLib.wrap(uint256(int256(outflow)) * 1e24)).unwrap() / 1e24)
    );
    return min(inflow, outflowAsInflow);
  }

  function maxOutflow(ExchangeForkTest ctx, address from, address to) internal view returns (int48) {
    return maxInflow(ctx, to, from);
  }

  function maxInflow(ExchangeForkTest ctx, address from) internal view returns (int48) {
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

  function maxOutflow(ExchangeForkTest ctx, address to) internal view returns (int48) {
    ITradingLimits.Config memory limitConfig = tradingLimitsConfig(ctx, to);
    ITradingLimits.State memory limitState = refreshedTradingLimitsState(ctx, to);
    int48 maxOutflowL0 = limitConfig.limit0 + limitState.netflow0;
    int48 maxOutflowL1 = limitConfig.limit1 + limitState.netflow1;
    int48 maxOutflowLG = limitConfig.limitGlobal + limitState.netflowGlobal;

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
}
