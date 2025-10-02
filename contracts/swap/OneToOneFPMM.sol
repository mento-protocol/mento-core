// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { FPMM } from "./FPMM.sol";

contract OneToOneFPMM is FPMM {
  /**
   * @notice Contract constructor
   * @param disable Boolean to disable initializers for implementation contract
   */
  constructor(bool disable) FPMM(disable) {}

  function _getRateFeed() internal view override returns (uint256 rateNumerator, uint256 rateDenominator) {
    FPMMStorage storage $ = _getFPMMStorage();

    // Check if trading is suspended via breaker box
    require(!$.oracleAdapter.isTradingSuspended($.referenceRateFeedID), "OracleAdapter: TRADING_SUSPENDED");

    // Always return 1:1 rate for stablecoin swaps
    return (1e18, 1e18);
  }
}
