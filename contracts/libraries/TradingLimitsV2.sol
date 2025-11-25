// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

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
 * 2. No rounding of small amounts to 1 unit. For tokens with more than 15 decimals
 *    the amount is scaled down to 15 decimals.
 * 3. Larger data types: int96 for netflows, int120 for limits
 * 4. Removed global limit functionality
 * 5. Fixed timeframes: 5 minutes for L0, 1 day for L1
 */
library TradingLimitsV2 {
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
    if (self.limit0 > 0 && self.limit1 > 0 && self.limit1 <= self.limit0) {
      revert ITradingLimitsV2.Limit1MustBeGreaterThanLimit0();
    }
    if (0 == self.decimals || 18 < self.decimals) {
      revert ITradingLimitsV2.InvalidDecimals();
    }
  }

  /**
   * @notice Verify a trading limit State with a provided Config.
   * @dev Reverts if the limits are exceeded.
   * The netflows and limits are stored with 15 decimals of precision.
   * @param self the trading limit State to check.
   * @param config the trading limit Config to check against.
   */
  function verify(ITradingLimitsV2.State memory self, ITradingLimitsV2.Config memory config) internal pure {
    if (config.limit0 > 0 && (self.netflow0 < -config.limit0 || self.netflow0 > config.limit0)) {
      revert ITradingLimitsV2.L0LimitExceeded();
    }
    if (config.limit1 > 0 && (self.netflow1 < -config.limit1 || self.netflow1 > config.limit1)) {
      revert ITradingLimitsV2.L1LimitExceeded();
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
    if (config.limit0 == 0) {
      self.netflow0 = 0;
    }
    if (config.limit1 == 0) {
      self.netflow1 = 0;
    }
    return self;
  }

  /**
   * @notice Apply trading limits by updating state and verifying against config.
   * @dev This is the main entry point for applying trading limits. It loads state and config
   * in memory, updates the state, verifies limits, and returns the updated TradingLimits struct.
   * The caller should write the returned struct back to storage.
   * @param self the trading limits (state + config) to apply.
   * @param amountIn amount of token flowing in.
   * @param amountOut amount of token flowing out.
   * @return the updated trading limits.
   */
  function applyTradingLimits(
    ITradingLimitsV2.TradingLimits memory self,
    uint256 amountIn,
    uint256 amountOut
  ) internal view returns (ITradingLimitsV2.State memory) {
    if (self.config.limit0 == 0 && self.config.limit1 == 0) {
      return self.state;
    }

    int256 deltaFlow = int256(amountIn) - int256(amountOut);
    self.state = update(self.state, self.config, deltaFlow);
    verify(self.state, self.config);
    return self.state;
  }

  /**
   * @notice Updates a trading limit State in the context of a Config with the deltaFlow provided.
   * @dev Reverts if the values provided cause overflows.
   * The deltaFlow is provided in the token's native decimals and is scaled to 15 decimals internally.
   * Small amounts that scale to 0 are ignored.
   * @param self the trading limit State to update.
   * @param config the trading limit Config for the provided State.
   * @param _deltaFlow the delta flow to add to the netflow, in the token's native decimals.
   * @return State the updated state.
   */
  function update(
    ITradingLimitsV2.State memory self,
    ITradingLimitsV2.Config memory config,
    int256 _deltaFlow
  ) internal view returns (ITradingLimitsV2.State memory) {
    if (_deltaFlow == 0) {
      return self;
    }

    int96 scaledDelta = scaleValue(_deltaFlow, config.decimals);

    if (config.limit0 > 0) {
      if (block.timestamp > self.lastUpdated0 + TIMESTEP0) {
        self.netflow0 = 0;
        self.lastUpdated0 = uint32(block.timestamp);
      }
      self.netflow0 = safeAdd(self.netflow0, scaledDelta);
    }

    if (config.limit1 > 0) {
      if (block.timestamp > self.lastUpdated1 + TIMESTEP1) {
        self.netflow1 = 0;
        self.lastUpdated1 = uint32(block.timestamp);
      }
      self.netflow1 = safeAdd(self.netflow1, scaledDelta);
    }

    return self;
  }

  /**
   * @notice Scale a value from token decimals to internal precision (15 decimals).
   * @dev Handles both scaling up (for tokens with < 15 decimals) and scaling down (> 15 decimals).
   * @param value the value in token decimals.
   * @param decimals the token's decimal places.
   * @return the scaled value in 15 decimal precision.
   */
  function scaleValue(int256 value, uint8 decimals) internal pure returns (int96) {
    if (value == 0) return 0;

    int256 scaledValue;

    scaledValue = (value * int256(10 ** INTERNAL_DECIMALS)) / int256(10 ** decimals);

    if (scaledValue > MAX_INT96 || scaledValue < MIN_INT96) revert ITradingLimitsV2.ValueExceedsInt96Bounds();
    return int96(scaledValue);
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
    if (c < MIN_INT96 || c > MAX_INT96) revert ITradingLimitsV2.Int96AdditionOverflow();
    return int96(c);
  }
}
