// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ITradingLimitsV2 {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  // @notice Throw when limit1 is not greater than limit0 when both are active
  error Limit1MustBeGreaterThanLimit0();
  // @notice Throw when L0 trading limit is exceeded
  error L0LimitExceeded();
  // @notice Throw when L1 trading limit is exceeded
  error L1LimitExceeded();
  // @notice Throw when a value exceeds int96 bounds during scaling
  error ValueExceedsInt96Bounds();
  // @notice Throw when int96 addition causes overflow
  error Int96AdditionOverflow();
  // @notice Throw when decimals are out of range [1, 18]
  error InvalidDecimals();

  /* ============================================================ */
  /* ======================== Structs ============================ */
  /* ============================================================ */

  /**
   * @dev The State struct contains the current state of a trading limit config.
   * @param lastUpdated0 The timestamp of the last reset of netflow0.
   * @param lastUpdated1 The timestamp of the last reset of netflow1.
   * @param netflow0 The current netflow of the asset for limit0 (L0), stored with 15 decimals of precision.
   * @param netflow1 The current netflow of the asset for limit1 (L1), stored with 15 decimals of precision.
   */
  struct State {
    uint32 lastUpdated0;
    uint32 lastUpdated1;
    int96 netflow0;
    int96 netflow1;
  }

  /**
   * @dev The Config struct contains the configuration of trading limits.
   * @param limit0 The limit0 for the asset, stored with 15 decimals of precision.
   * @param limit1 The limit1 for the asset, stored with 15 decimals of precision.
   * @param decimals The number of decimals of the token the limits are configured for.
   */
  struct Config {
    int120 limit0;
    int120 limit1;
    uint8 decimals;
  }

  struct TradingLimits {
    State state;
    Config config;
  }
}
