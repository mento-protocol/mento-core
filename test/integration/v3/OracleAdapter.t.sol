// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";

contract OracleAdapterIntegrationTest is OracleAdapterDeployer {
  // Sorted oracles always returns 1e24 as the denominator, which is then divided by 1e6 in the OracleAdapter
  uint256 constant DENOMINATOR = 1e18;

  uint256 constant FIXED1 = 1e24;

  function test_oracleAdapter_revertsWhenMarketIsClosed() public {
    _deployOracleAdapter();

    // One second before market close (2025-10-24 20:59:59)
    vm.warp(1761339599);

    uint256 beforeCloseCDPFPMMRate = 2.0001e24;
    _reportCDPFPMMRate(beforeCloseCDPFPMMRate);
    assertCDPFPMMRateEqual(beforeCloseCDPFPMMRate / 1e6, DENOMINATOR);

    uint256 beforeCloseReserveFPMMRate = 1.0001e24;
    _reportReserveFPMMRate(beforeCloseReserveFPMMRate);
    assertReserveFPMMRateEqual(beforeCloseReserveFPMMRate / 1e6, DENOMINATOR);

    skip(1 seconds);

    // Sorted oracles no longer accepts reports during closed market hours
    vm.expectRevert("MarketHoursBreaker: FX market is closed");
    _reportCDPFPMMRate(3e24);

    vm.expectRevert("MarketHoursBreaker: FX market is closed");
    _reportReserveFPMMRate(1.0002e24);

    vm.expectRevert(IOracleAdapter.FXMarketClosed.selector);
    $oracle.adapter.getFXRateIfValid($addresses.referenceRateFeedCDPFPMM);

    vm.expectRevert(IOracleAdapter.FXMarketClosed.selector);
    $oracle.adapter.getFXRateIfValid($addresses.referenceRateFeedReserveFPMM);

    // One second before market opening (2025-10-26 22:59:59)
    skip(2 days + 2 hours - 1 seconds);

    vm.expectRevert("MarketHoursBreaker: FX market is closed");
    _reportCDPFPMMRate(2.01e24);

    vm.expectRevert(IOracleAdapter.FXMarketClosed.selector);
    $oracle.adapter.getFXRateIfValid($addresses.referenceRateFeedCDPFPMM);

    vm.expectRevert("MarketHoursBreaker: FX market is closed");
    _reportReserveFPMMRate(1.0002e24);

    vm.expectRevert(IOracleAdapter.FXMarketClosed.selector);
    $oracle.adapter.getFXRateIfValid($addresses.referenceRateFeedReserveFPMM);

    skip(1 seconds); // Markets are now open

    uint256 newCDPFPMMRate = 2.05e24;
    _reportCDPFPMMRate(newCDPFPMMRate);
    assertCDPFPMMRateEqual(newCDPFPMMRate / 1e6, DENOMINATOR);

    uint256 newReserveFPMMRate = 1.0005e24;
    _reportReserveFPMMRate(newReserveFPMMRate);
    assertReserveFPMMRateEqual(newReserveFPMMRate / 1e6, DENOMINATOR);
  }

  function test_oracleAdapter_revertsWhenMedianDeltaBreakerTrips() public {
    _deployOracleAdapter();

    (uint256 initialRate, ) = $oracle.adapter.getFXRateIfValid($addresses.referenceRateFeedCDPFPMM);
    assertEq($oracle.adapter.getTradingMode($addresses.referenceRateFeedCDPFPMM), 0);

    uint256 threshold = $oracle.medianDeltaBreaker.defaultRateChangeThreshold();

    uint256 priceThatTripsBreaker = (_toFixidity(initialRate) * (FIXED1 + threshold)) / FIXED1 + 1;
    _reportCDPFPMMRate(priceThatTripsBreaker);

    assertEq($oracle.adapter.getTradingMode($addresses.referenceRateFeedCDPFPMM), 1);

    // wait for the cooldown and report back a back to normal rate that resets the breaker
    uint256 backToNormalRate = _toFixidity(initialRate) + 0.2e24;
    skip($oracle.medianDeltaBreaker.getCooldown($addresses.referenceRateFeedCDPFPMM));
    _reportCDPFPMMRate(backToNormalRate);

    assertEq($oracle.adapter.getTradingMode($addresses.referenceRateFeedCDPFPMM), 0);
    assertCDPFPMMRateEqual(backToNormalRate / 1e6, DENOMINATOR);
  }

  function test_oracleAdapter_revertsWhenValueDeltaBreakerTrips() public {
    _deployOracleAdapter();

    assertEq($oracle.adapter.getTradingMode($addresses.referenceRateFeedReserveFPMM), 0);

    uint256 threshold = $oracle.valueDeltaBreaker.defaultRateChangeThreshold();
    uint256 referenceValue = $oracle.valueDeltaBreaker.referenceValues($addresses.referenceRateFeedReserveFPMM);

    uint256 priceThatTripsBreaker = (referenceValue * (FIXED1 + threshold)) / FIXED1 + 1;
    _reportReserveFPMMRate(priceThatTripsBreaker);

    assertEq($oracle.adapter.getTradingMode($addresses.referenceRateFeedReserveFPMM), 1);

    // wait for the cooldown and report back a back to normal rate that resets the breaker
    uint256 backToNormalRate = referenceValue + 0.001e24;
    skip($oracle.valueDeltaBreaker.getCooldown($addresses.referenceRateFeedReserveFPMM));
    _reportReserveFPMMRate(backToNormalRate);

    assertEq($oracle.adapter.getTradingMode($addresses.referenceRateFeedReserveFPMM), 0);
    assertReserveFPMMRateEqual(backToNormalRate / 1e6, DENOMINATOR);
  }

  function _toFixidity(uint256 rate) internal pure returns (uint256) {
    return rate * 1e6;
  }

  function assertCDPFPMMRateEqual(uint256 expectedNumerator, uint256 expectedDenominator) internal {
    (uint256 actualNumerator, uint256 actualDenominator) = $oracle.adapter.getFXRateIfValid(
      $addresses.referenceRateFeedCDPFPMM
    );
    assertEq(actualNumerator, expectedNumerator);
    assertEq(actualDenominator, expectedDenominator);
  }

  function assertReserveFPMMRateEqual(uint256 expectedNumerator, uint256 expectedDenominator) internal {
    (uint256 actualNumerator, uint256 actualDenominator) = $oracle.adapter.getFXRateIfValid(
      $addresses.referenceRateFeedReserveFPMM
    );
    assertEq(actualNumerator, expectedNumerator);
    assertEq(actualDenominator, expectedDenominator);
  }
}
