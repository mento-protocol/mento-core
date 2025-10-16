// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;
pragma experimental ABIEncoderV2;

import { ITradingLimitsV2 } from "contracts/interfaces/ITradingLimitsV2.sol";

/**
 * @title TradingLimitsV2
 * @author Mento Team
 * @notice This library provides data structs and utility functions for
 * defining and verifying trading limits on the netflow of an asset.
 * There are two limits that can be enabled:
 * - L0: Short-term limit with fixed 5-minute time window
 *       -limit0 <= netflow0 <= limit0
 * - L1: Medium-term limit with fixed 1-day time window
 *       -limit1 <= netflow1 <= limit1
 *
 * @dev All contained functions are pure or view and marked internal to
 * be inlined on consuming contracts at compile time for gas efficiency.
 * Both State and Config structs are designed to be packed in one
 * storage slot each.
 *
 * Key differences from V1:
 * 1. Netflows are stored with 15 decimals of precision internally
 * 2. Limits in Config are provided in the token's native decimals
 * 3. No rounding of small amounts to 1 unit
 * 4. Larger data types: int96 for netflows, int112 for limits
 * 5. Removed global limit functionality
 * 6. Fixed timeframes: 5 minutes for L0, 1 day for L1
 */
library TradingLimitsV2 {
  uint8 private constant L0 = 1; // 0b001 Limit0
  uint8 private constant L1 = 2; // 0b010 Limit1
  uint8 private constant INTERNAL_DECIMALS = 15;
  uint32 private constant TIMESTEP0 = 5 minutes; // 300 seconds
  uint32 private constant TIMESTEP1 = 1 days; // 86400 seconds
  int96 private constant MAX_INT96 = type(int96).max;
  int96 private constant MIN_INT96 = type(int96).min;

  /**
   * @notice Validate a trading limit configuration.
   * @dev Reverts if the configuration is malformed.
   * @param self the Config struct to check.
   */
  function validate(ITradingLimitsV2.Config memory self) internal pure {
    require(self.flags & L0 == 0 || self.limit0 > 0, "limit0 can't be zero if active");
    require(self.flags & L1 == 0 || self.limit1 > 0, "limit1 can't be zero if active");
    require(self.flags & (L0 | L1) != 3 || self.limit0 < self.limit1, "limit1 must be greater than limit0");
  }

  /**
   * @notice Verify a trading limit State with a provided Config.
   * @dev Reverts if the limits are exceeded.
   * The netflow values in State are stored with 15 decimals, while the limits
   * in Config are in the token's native decimals, so we need to scale the limits
   * for comparison.
   * @param self the trading limit State to check.
   * @param config the trading limit Config to check against.
   * @param decimals the number of decimals of the token being traded.
   */
  function verify(
    ITradingLimitsV2.State memory self,
    ITradingLimitsV2.Config memory config,
    uint8 decimals
  ) internal pure {
    if (config.flags & L0 > 0) {
      int96 scaledConfigLimit0 = scaleLimit(config.limit0, decimals);
      if (self.netflow0 < -scaledConfigLimit0 || self.netflow0 > scaledConfigLimit0) {
        revert("L0 Exceeded");
      }
    }
    if (config.flags & L1 > 0) {
      int96 scaledConfigLimit1 = scaleLimit(config.limit1, decimals);
      if (self.netflow1 < -scaledConfigLimit1 || self.netflow1 > scaledConfigLimit1) {
        revert("L1 Exceeded");
      }
    }
  }

  /**
   * @notice Reset an existing state with a new config.
   * It keeps netflows of enabled limits and resets when disabled.
   * It resets all timestamp checkpoints to reset time-window limits
   * on next swap.
   * @param self the trading limit state to reset.
   * @param config the updated config to reset against.
   * @return the reset state.
   */
  function reset(
    ITradingLimitsV2.State memory self,
    ITradingLimitsV2.Config memory config
  ) internal pure returns (ITradingLimitsV2.State memory) {
    // Ensure the next swap will reset the trading limits windows.
    self.lastUpdated0 = 0;
    self.lastUpdated1 = 0;
    if (config.flags & L0 == 0) {
      self.netflow0 = 0;
    }
    if (config.flags & L1 == 0) {
      self.netflow1 = 0;
    }
    return self;
  }

  /**
   * @notice Updates a trading limit State in the context of a Config with the deltaFlow provided.
   * @dev Reverts if the values provided cause overflows.
   * The deltaFlow is provided in the token's native decimals and is scaled to 15 decimals internally.
   * Small amounts that scale to 0 are ignored.
   * @param self the trading limit State to update.
   * @param config the trading limit Config for the provided State.
   * @param _deltaFlow the delta flow to add to the netflow, in the token's native decimals.
   * @param decimals the number of decimals the _deltaFlow is denominated in.
   * @return State the updated state.
   */
  function update(
    ITradingLimitsV2.State memory self,
    ITradingLimitsV2.Config memory config,
    int256 _deltaFlow,
    uint8 decimals
  ) internal view returns (ITradingLimitsV2.State memory) {
    if (_deltaFlow == 0) {
      return self;
    }

    int96 scaledDelta = scaleFlow(_deltaFlow, decimals);

    if (scaledDelta == 0) {
      return self;
    }

    if (config.flags & L0 > 0) {
      if (block.timestamp > self.lastUpdated0 + TIMESTEP0) {
        self.netflow0 = 0;
        self.lastUpdated0 = uint32(block.timestamp);
      }
      self.netflow0 = safeAdd(self.netflow0, scaledDelta);
    }

    if (config.flags & L1 > 0) {
      if (block.timestamp > self.lastUpdated1 + TIMESTEP1) {
        self.netflow1 = 0;
        self.lastUpdated1 = uint32(block.timestamp);
      }
      self.netflow1 = safeAdd(self.netflow1, scaledDelta);
    }

    return self;
  }

  /**
   * @notice Scale a flow amount from token decimals to internal precision (15 decimals).
   * @dev Handles both scaling up (for tokens with < 15 decimals) and scaling down (> 15 decimals).
   * @param flow the flow amount in token decimals.
   * @param decimals the token's decimal places.
   * @return the scaled flow amount in 15 decimal precision.
   */
  function scaleFlow(int256 flow, uint8 decimals) internal pure returns (int96) {
    int256 scaledFlow;

    if (decimals == INTERNAL_DECIMALS) {
      scaledFlow = flow;
    } else if (decimals < INTERNAL_DECIMALS) {
      uint256 scaleFactor = 10 ** (INTERNAL_DECIMALS - decimals);
      scaledFlow = flow * int256(scaleFactor);
    } else {
      uint256 scaleFactor = 10 ** (decimals - INTERNAL_DECIMALS);
      scaledFlow = flow / int256(scaleFactor);
    }

    require(scaledFlow <= MAX_INT96 && scaledFlow >= MIN_INT96, "Flow exceeds int96 bounds");
    return int96(scaledFlow);
  }

  /**
   * @notice Scale a limit from token decimals to internal precision (15 decimals).
   * @dev Used to scale config limits for comparison with state netflows.
   * @param limit the limit amount in token decimals.
   * @param decimals the token's decimal places.
   * @return the scaled limit in 15 decimal precision.
   */
  function scaleLimit(int112 limit, uint8 decimals) internal pure returns (int96) {
    if (limit == 0) return 0;

    int256 scaledLimit;

    if (decimals == INTERNAL_DECIMALS) {
      scaledLimit = int256(limit);
    } else if (decimals < INTERNAL_DECIMALS) {
      uint256 scaleFactor = 10 ** (INTERNAL_DECIMALS - decimals);
      scaledLimit = int256(limit) * int256(scaleFactor);
    } else {
      uint256 scaleFactor = 10 ** (decimals - INTERNAL_DECIMALS);
      scaledLimit = int256(limit) / int256(scaleFactor);
    }

    require(scaledLimit <= MAX_INT96 && scaledLimit >= MIN_INT96, "Limit exceeds int96 bounds");
    return int96(scaledLimit);
  }

  /**
   * @notice Safe add two int96 values.
   * @dev Reverts if addition causes over/underflow.
   * @param a first value to add.
   * @param b second value to add.
   * @return result of addition.
   */
  function safeAdd(int96 a, int96 b) internal pure returns (int96) {
    int256 c = int256(a) + int256(b);
    require(c >= MIN_INT96 && c <= MAX_INT96, "int96 addition overflow");
    return int96(c);
  }
}
