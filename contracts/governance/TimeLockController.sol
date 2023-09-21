// SPDX-Licence-Identifier: MIT
pragma solidity 0.8.18;
// solhint-disable max-line-length
// solhint-disable func-name-mixedcase

import { TimelockControllerUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/TimelockControllerUpgradeable.sol";

/**
 * @title TimelockController
 * @author Mento Labs
 * @notice A contract that manages the timelock functionality.
 * @dev Ownable contracts should be owned by TimelockController
 */
contract TimelockController is TimelockControllerUpgradeable {
  /**
   * @notice Initializes the TimelockController with the provided parameters.
   * @param minDelay The minimum delay before a proposal can be executed.
   * @param proposers List of addresses that are allowed to queue and cancel operations.
   * @param executors List of addresses that are allowed to execute proposals. address(0) can be used to allow any account.
   * @param admin The admin address that will be used to set the proposer role and then will be renounced.
   */
  function __MentoTimelockController_init(
    uint256 minDelay,
    address[] memory proposers,
    address[] memory executors,
    address admin
  ) external initializer {
    __TimelockController_init(minDelay, proposers, executors, admin);
  }
}
