// SPDX-License-Identifier: MIT
// solhint-disable max-line-length, function-max-lines

pragma solidity 0.8.24;
import { TestStorage } from "./TestStorage.sol";

import { OracleAdapter } from "contracts/oracles/OracleAdapter.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";

contract OracleAdapterDeployer is TestStorage {
  function _deployOracleAdapter() internal {
    $oracle.adapter = IOracleAdapter(new OracleAdapter(false));
    vm.label(address($oracle.adapter), "OracleAdapter");
    $oracle.adapter.initialize(
      $addresses.sortedOracles,
      $addresses.breakerBox,
      $addresses.marketHoursBreaker,
      $addresses.governance
    );

    _enableOneToOneFPMM();
    _setFxRate(2e18, 1e18);

    $oracle.deployed = true;
  }

  function _setFxRate(uint256 numerator, uint256 denominator) internal {
    vm.mockCall(
      address($oracle.adapter),
      abi.encodeWithSelector(IOracleAdapter.getFXRateIfValid.selector, $addresses.referenceRateFeedCDPFPMM),
      abi.encode(numerator, denominator)
    );
  }

  function _enableOneToOneFPMM() internal {
    vm.mockCall(
      address($oracle.adapter),
      abi.encodeWithSelector(IOracleAdapter.ensureRateValid.selector, $addresses.referenceRateFeedReserveFPMM),
      bytes("")
    );
  }
}
