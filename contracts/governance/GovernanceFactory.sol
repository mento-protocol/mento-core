// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { TimelockController } from "./TimelockController.sol";
import { MentoGovernor } from "./MentoGovernor.sol";
import { TokenFactory } from "./TokenFactory.sol";

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IVotesUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesUpgradeable.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title Governance Factory
 * @author Mento Labs
 * @notice Factory for creating and initializing the governance related contracts
 **/
contract GovernanceFactory is Ownable {
  /// @dev Event emitted when the governance system is successfully created
  event GovernanceCreated(address timelock, address governor);

  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;

  bool public initialized; // Indicates if the governance system has been created

  // Timelock configuration
  uint256 public constant TIMELOCK_DELAY = 2 days;

  // Governor configuration
  uint256 public constant GOVERNOR_VOTING_DELAY = 1; // Voting start the next block
  uint256 public constant GOVERNOR_VOTING_PERIOD = 120_960; // Voting period for the governor (7 days in blocks CELO)
  uint256 public constant GOVERNOR_PROPOSAL_THRESHOLD = 1_000e18;
  uint256 public constant GOVERNOR_QUORUM = 2; // Quorum percentage for the governor

  /// @notice Creates the factory with the owner address
  /// @param owner_ Address of the owner, Celo governance
  constructor(address owner_) {
    transferOwnership(owner_);
  }

  /// @notice Creates and initializes the governance system contracts
  /// @param communityMultisig Address of the community's multisig wallet with the veto rights
  /// @param timelockImplementation Address of the implementation of timelock
  /// @param governorImplementation Address of the implementation of Mento Governor
  /// @param tokenFactory Address of the Token Factory
  /// @dev This can only be called by the owner and only once
  function createGovernanceContracts(
    address communityMultisig,
    address timelockImplementation,
    address governorImplementation,
    TokenFactory tokenFactory
  ) external onlyOwner {
    require(!initialized, "GovernanceFactory: governance already created");
    require(tokenFactory.initialized(), "GovernanceFactory: TokenFactory should be initialized first");
    initialized = true;

    // Creation
    TransparentUpgradeableProxy timelockProxy = new TransparentUpgradeableProxy(timelockImplementation, msg.sender, "");
    timelockController = TimelockController(payable(address(timelockProxy)));

    TransparentUpgradeableProxy governorProxy = new TransparentUpgradeableProxy(governorImplementation, msg.sender, "");
    mentoGovernor = MentoGovernor(payable(address(governorProxy)));

    // Initializations
    address[] memory proposers = new address[](1);
    address[] memory executors = new address[](1);
    proposers[0] = address(mentoGovernor); // Governor can propose and cancel
    executors[0] = address(0); // Anyone can execute
    timelockController.__MentoTimelockController_init(
      TIMELOCK_DELAY,
      proposers,
      executors,
      address(0), // no admin, other roles are preset
      communityMultisig
    );

    mentoGovernor.__MentoGovernor_init(
      IVotesUpgradeable(address(tokenFactory.locking())),
      timelockController,
      GOVERNOR_VOTING_DELAY,
      GOVERNOR_VOTING_PERIOD,
      GOVERNOR_PROPOSAL_THRESHOLD,
      GOVERNOR_QUORUM
    );

    emit GovernanceCreated(address(timelockController), address(mentoGovernor));
  }
}
