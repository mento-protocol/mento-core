// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { FPMM } from "./FPMM.sol";

contract OneToOneFPMM is FPMM {
  /**
   * @notice Contract constructor
   * @param disable Boolean to disable initializers for implementation contract
   */
  constructor(bool disable) FPMM(disable) {}

  function _getRateFeed() internal view override returns (uint256 rateNumerator, uint256 rateDenominator) {
    FPMMStorage storage $ = _getFPMMStorage();

    // Ensure rate feed is valid (checks trading mode and rate freshness)
    $.oracleAdapter.ensureRateValid($.referenceRateFeedID);

    // Always return 1:1 rate for stablecoin swaps
    return (1e18, 1e18);
  }
}
