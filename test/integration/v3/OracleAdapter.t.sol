// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";

contract OracleAdapterIntegrationTest is OracleAdapterDeployer {
  // Sorted oracles always returns 1e24 as the denominator, which is then divided by 1e6 in the OracleAdapter
  uint256 constant DENOMINATOR = 1e18;

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

    // Markets are now open
    skip(1 seconds);

    uint256 newCDPFPMMRate = 2.05e24;
    _reportCDPFPMMRate(newCDPFPMMRate);
    assertCDPFPMMRateEqual(newCDPFPMMRate / 1e6, DENOMINATOR);

    uint256 newReserveFPMMRate = 1.0005e24;
    _reportReserveFPMMRate(newReserveFPMMRate);
    assertReserveFPMMRateEqual(newReserveFPMMRate / 1e6, DENOMINATOR);
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
