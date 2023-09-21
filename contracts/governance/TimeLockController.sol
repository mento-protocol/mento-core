// SPDX-Licence-Identifier: MIT
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { TimelockControllerUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/TimelockControllerUpgradeable.sol";

contract TimelockController is TimelockControllerUpgradeable {
  function __MentoTimelockController_init(
    uint256 minDelay, // TBD
    address[] memory proposers,
    address[] memory executors,
    address admin // will be used to set proposer role and then will be renounced
  ) external initializer {
    __TimelockController_init(minDelay, proposers, executors, admin);
  }
}
