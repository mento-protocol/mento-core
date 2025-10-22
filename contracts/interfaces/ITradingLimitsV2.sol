// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ITradingLimitsV2 {
  /* ============================================================ */
  /* ======================== Errors ============================ */
  /* ============================================================ */

  // @notice Throw when limit0 is zero but flag is active
  error Limit0ZeroWhenActive();
  // @notice Throw when limit1 is zero but flag is active
  error Limit1ZeroWhenActive();
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
   * @param limit0 The limit0 for the asset, using the token's native decimals.
   * @param limit1 The limit1 for the asset, using the token's native decimals.
   * @param flags A bitfield of flags to enable/disable the individual limits.
   */
  struct Config {
    int112 limit0;
    int112 limit1;
    uint8 flags;
  }

  struct TradingLimits {
    State state;
    Config config;
  }
}
