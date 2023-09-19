// SPDX-Licence-Identifier: MIT
pragma solidity 0.8.18;

import { TimelockControllerUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/TimelockControllerUpgradeable.sol";

contract MentoTimelockController is TimelockControllerUpgradeable {
  function __MentoTimelockController_init(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin
  ) external initializer {
    __TimelockController_init(minDelay, proposers, executors, admin);
  }
}
