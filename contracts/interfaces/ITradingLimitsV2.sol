// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >0.5.13 <0.9;

interface ITradingLimitsV2 {
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
}
