// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { MentoToken } from "./MentoToken.sol";
import { Emission } from "./Emission.sol";
import { Airgrab } from "./Airgrab.sol";
import { TimelockController } from "./TimelockController.sol";
import { MentoGovernor } from "./MentoGovernor.sol";
import { Locking } from "./locking/Locking.sol";

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { IVotesUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesUpgradeable.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title Factory
 * @author Mento Labs
 * @notice Factory for creating and initializing the entire governance system
 * including the token, emission, airgrab, and governance related contracts.
 **/
contract Factory is Ownable {
  /// @dev Event emitted when the governance system is successfully created
  event GovernanceCreated(
    address mentoToken,
    address emission,
    address airgrab,
    address mentoMultisig,
    address vesting,
    address treasury,
    address locking,
    address timelock,
    address governor
  );

  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;
  Locking public locking;

  bool public initialized; // Indicates if the governance system has been created
  address public vesting;
  address public mentoMultisig;
  address public treasury;

  // Airgrab configuration
  uint32 public constant AIRGRAB_LOCK_SLOPE = 104; // Slope duration for the airgrabed tokens in weeks

  uint32 public constant AIRGRAB_LOCK_CLIFF = 0; // Cliff duration for the airgrabed tokens in weeks
  uint256 public constant AIRGRAB_DURATION = 365 days;
  uint256 public constant FRACTAL_MAX_AGE = 180 days; // Maximum age of the kyc for the airgrab

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
  /// @param vesting_ Address of the vesting contract
  /// @param mentoMultisig_ Address of the mento multisig
  /// @param treasury_ Address of the treasury
  /// @param communityMultisig Address of the community's multisig wallet with the veto rights
  /// @param airgrabRoot Root hash for the airgrab Merkle tree
  /// @param fractalSigner Signer of fractal kyc
  /// @dev This can only be called by the owner and only once
  function createGovernance(
    address vesting_,
    address mentoMultisig_,
    address treasury_,
    address communityMultisig,
    bytes32 airgrabRoot,
    address fractalSigner
  ) external onlyOwner {
    require(!initialized, "Factory: governance already created");
    initialized = true;

    // ---------------------------------- //
    // TODO: Replace with actual contracts
    vesting = vesting_;
    treasury = treasury_;
    // ---------------------------------- //

    mentoMultisig = mentoMultisig_;

    // Creation
    emission = new Emission();
    uint256 airgrabEnds = block.timestamp + AIRGRAB_DURATION;
    airgrab = new Airgrab(
      airgrabRoot,
      fractalSigner,
      FRACTAL_MAX_AGE,
      airgrabEnds,
      AIRGRAB_LOCK_CLIFF,
      AIRGRAB_LOCK_SLOPE
    );
    mentoToken = new MentoToken(vesting, mentoMultisig, address(airgrab), treasury, address(emission));
    timelockController = new TimelockController();
    mentoGovernor = new MentoGovernor();
    locking = new Locking();

    // Initializations
    airgrab.initialize(address(mentoToken), address(locking), treasury);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(treasury);
    // we start the locking contract from week 1 with min slope duration of 1
    locking.__Locking_init(IERC20Upgradeable(address(mentoToken)), uint32(locking.getWeek() - 1), 0, 1);

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
      IVotesUpgradeable(address(locking)),
      timelockController,
      GOVERNOR_VOTING_DELAY,
      GOVERNOR_VOTING_PERIOD,
      GOVERNOR_PROPOSAL_THRESHOLD,
      GOVERNOR_QUORUM
    );

    emission.transferOwnership(address(timelockController));
    locking.transferOwnership(address(timelockController));

    emit GovernanceCreated(
      address(mentoToken),
      address(emission),
      address(airgrab),
      mentoMultisig,
      vesting,
      treasury,
      address(locking),
      address(timelockController),
      address(mentoGovernor)
    );
  }
}
