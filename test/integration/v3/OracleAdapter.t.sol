// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { OracleAdapterDeployer } from "test/integration/v3/OracleAdapterDeployer.sol";

contract OracleAdapterIntegrationTest is OracleAdapterDeployer {
  function test_oracleAdapter_medianDeltaBreakerTrips() public {
    _deployOracleAdapter();
  }
}
