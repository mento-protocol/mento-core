// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { IMedianDeltaBreaker } from "contracts/interfaces/IMedianDeltaBreaker.sol";
import { IMarketHoursBreaker } from "contracts/interfaces/IMarketHoursBreaker.sol";
import { MarketHoursBreaker } from "contracts/oracles/breakers/MarketHoursBreaker.sol";

import { addresses } from "mento-std/Array.sol";

contract OracleAdapterDeployer is TestStorage {
  function _deployOracleAdapter() internal {
    _deploySortedOracles();
    _deployCircuitBreaker();

    $oracle.adapter = IOracleAdapter(new OracleAdapter(false));
    vm.label(address($oracle.adapter), "OracleAdapter");
    $oracle.adapter.initialize(
      address($oracle.sortedOracles),
      address($oracle.breakerBox),
      address($oracle.marketHoursBreaker),
      $addresses.governance
    );

    reportRate($addresses.referenceRateFeedCDPFPMM, 2e24);
    reportRate($addresses.referenceRateFeedReserveFPMM, 1e24);

    $oracle.deployed = true;
  }

  function _refreshOracleRates() internal {
    (uint256 CDPFPMMRate, ) = $oracle.sortedOracles.medianRate($addresses.referenceRateFeedCDPFPMM);
    (uint256 reserveFPMMRate, ) = $oracle.sortedOracles.medianRate($addresses.referenceRateFeedReserveFPMM);

    require(CDPFPMMRate > 0 && reserveFPMMRate > 0, "OracleAdapterDeployer: no pre-existing rate to refresh");

    reportRate($addresses.referenceRateFeedCDPFPMM, CDPFPMMRate);
    reportRate($addresses.referenceRateFeedReserveFPMM, reserveFPMMRate);
  }

  function reportCDPFPMMRate(uint256 rate) internal {
    reportRate($addresses.referenceRateFeedCDPFPMM, rate);
  }

  function reportReserveFPMMRate(uint256 rate) internal {
    reportRate($addresses.referenceRateFeedReserveFPMM, rate);
  }

  function reportRate(address rateFeedID, uint256 rate) internal {
    require(
      rateFeedID == $addresses.referenceRateFeedCDPFPMM || rateFeedID == $addresses.referenceRateFeedReserveFPMM,
      "Invalid rate feed ID"
    );

    vm.prank($addresses.whitelistedOracle);
    $oracle.sortedOracles.report(rateFeedID, rate, address(0), address(0));

    (uint256 numerator, ) = $oracle.sortedOracles.medianRate(rateFeedID);
    assertEq(numerator, rate);
  }

  function _deploySortedOracles() private {
    $oracle.sortedOracles = ISortedOracles(deployCode("SortedOracles", abi.encode(true)));
    $oracle.sortedOracles.initialize(5 minutes);
    assertEq($oracle.sortedOracles.reportExpirySeconds(), 5 minutes);

    $oracle.sortedOracles.addOracle($addresses.referenceRateFeedCDPFPMM, $addresses.whitelistedOracle);
    $oracle.sortedOracles.addOracle($addresses.referenceRateFeedReserveFPMM, $addresses.whitelistedOracle);
  }

  function _deployCircuitBreaker() private {
    address[] memory feeds = addresses($addresses.referenceRateFeedCDPFPMM, $addresses.referenceRateFeedReserveFPMM);

    $oracle.breakerBox = IBreakerBox(
      deployCode("BreakerBox", abi.encode(feeds, $oracle.sortedOracles, $addresses.governance))
    );
    vm.label(address($oracle.breakerBox), "BreakerBox");

    $oracle.marketHoursBreaker = IMarketHoursBreaker(new MarketHoursBreaker());
    vm.label(address($oracle.marketHoursBreaker), "MarketHoursBreaker");

    $oracle.medianDeltaBreaker = IMedianDeltaBreaker(
      deployCode(
        "MedianDeltaBreaker",
        abi.encode(
          10 minutes,
          0.10 * 10 ** 24, // 10% change before tripping breaker
          $oracle.sortedOracles,
          address($oracle.breakerBox),
          new address[](0),
          new uint256[](0),
          new uint256[](0),
          $addresses.governance
        )
      )
    );
    vm.label(address($oracle.medianDeltaBreaker), "MedianDeltaBreaker");

    vm.startPrank($addresses.governance);
    $oracle.breakerBox.addBreaker(address($oracle.medianDeltaBreaker), 1);
    $oracle.breakerBox.addBreaker(address($oracle.marketHoursBreaker), 1);

    $oracle.breakerBox.toggleBreaker(address($oracle.medianDeltaBreaker), $addresses.referenceRateFeedCDPFPMM, true);
    $oracle.breakerBox.toggleBreaker(address($oracle.marketHoursBreaker), $addresses.referenceRateFeedCDPFPMM, true);
    $oracle.breakerBox.toggleBreaker(
      address($oracle.medianDeltaBreaker),
      $addresses.referenceRateFeedReserveFPMM,
      true
    );
    $oracle.breakerBox.toggleBreaker(
      address($oracle.marketHoursBreaker),
      $addresses.referenceRateFeedReserveFPMM,
      true
    );
    vm.stopPrank();

    $oracle.sortedOracles.setBreakerBox($oracle.breakerBox);
  }
}
