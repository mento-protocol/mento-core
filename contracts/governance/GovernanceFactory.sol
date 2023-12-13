// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { MentoToken } from "./MentoToken.sol";
import { Emission } from "./Emission.sol";
import { Airgrab } from "./Airgrab.sol";
import { TimelockController } from "./TimelockController.sol";
import { MentoGovernor } from "./MentoGovernor.sol";
import { Locking } from "./locking/Locking.sol";

import { AirgrabDeployerLib } from "./deployers/AirgrabDeployerLib.sol";
import { EmissionDeployerLib } from "./deployers/EmissionDeployerLib.sol";
import { LockingDeployerLib } from "./deployers/LockingDeployerLib.sol";
import { MentoGovernorDeployerLib } from "./deployers/MentoGovernorDeployerLib.sol";
import { MentoTokenDeployerLib } from "./deployers/MentoTokenDeployerLib.sol";
import { TimelockControllerDeployerLib } from "./deployers/TimelockControllerDeployerLib.sol";
import { ProxyDeployerLib } from "./deployers/ProxyDeployerLib.sol";

import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { IVotesUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/governance/extensions/GovernorVotesUpgradeable.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title GovernanceFactory
 * @author Mento Labs
 * @notice Factory for creating and initializing the entire governance system
 * including the MENTO token, locking, emission, airgrab, and governance-related contracts.
 **/
contract GovernanceFactory is Ownable {
  /// @dev Event emitted when the governance system has been successfully created
  event GovernanceCreated(
    address proxyAdmin,
    address emission,
    address mentoToken,
    address airgrab,
    address locking,
    address governanceTimelock,
    address mentoGovernor,
    address mentoLabsTreasury,
    address mentoLabsMultiSig
  );

  ProxyAdmin public proxyAdmin;
  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public governanceTimelock;
  MentoGovernor public mentoGovernor;
  Locking public locking;
  TimelockController public mentoLabsTreasuryTimelock;

  address public mentoLabsMultiSig;
  address public watchdogMultiSig;
  address public communityFund;

  // Indicates if the governance system has been created
  bool public initialized;

  // Airgrab configuration
  uint32 public constant AIRGRAB_LOCK_SLOPE = 104; // Slope duration for the airgrabed tokens in weeks
  uint32 public constant AIRGRAB_LOCK_CLIFF = 0; // Cliff duration for the airgrabed tokens in weeks
  uint256 public constant AIRGRAB_DURATION = 365 days;
  uint256 public constant FRACTAL_MAX_AGE = 180 days; // Maximum age of the kyc for the airgrab

  // Governance Timelock configuration
  uint256 public constant GOVERNANCE_TIMELOCK_DELAY = 2 days;

  // Governor configuration
  uint256 public constant GOVERNOR_VOTING_DELAY = 0; // Delay time in blocks between proposal creation and the start of voting.
  uint256 public constant GOVERNOR_VOTING_PERIOD = 120_960; // Voting period in blocks for the governor (7 days in blocks CELO)
  uint256 public constant GOVERNOR_PROPOSAL_THRESHOLD = 1_000e18;
  uint256 public constant GOVERNOR_QUORUM = 2; // Quorum percentage for the governor

  // Mento Labs Treasury Timelock configuration:
  // 7 days (gov voting period) + 2 days (gov timelock) + 4 days (buffer)
  uint256 public constant MENTOLABS_TREASURY_TIMELOCK_DELAY = 13 days;

  /**
   * @notice Creates the factory contract with the owner address
   * @param owner_ Address of the owner, will be Celo governance
   */
  constructor(address owner_) {
    transferOwnership(owner_);
  }

  /**
   * @notice Creates and initializes the governance system contracts
   * @param mentoLabsMultiSig_ Address of the Mento Labs multisig from where the team allocation will be vested
   * @param watchdogMultiSig_ Address of the community's multisig wallet with the veto rights
   * @param communityFund_ Address of the community fund that will receive the unclaimed airgrab tokens
   * @param airgrabRoot Root hash for the airgrab Merkle tree
   * @param fractalSigner Signer of fractal kyc
   * @dev Can only be called by the owner and only once
   */
  // solhint-disable-next-line function-max-lines
  function createGovernance(
    address mentoLabsMultiSig_,
    address watchdogMultiSig_,
    address communityFund_,
    bytes32 airgrabRoot,
    address fractalSigner
  ) external onlyOwner {
    require(!initialized, "Factory: governance already created");
    initialized = true;

    mentoLabsMultiSig = mentoLabsMultiSig_;
    watchdogMultiSig = watchdogMultiSig_;
    communityFund = communityFund_;

    // Precalculated contract addresses:
    address emissionPrecalculated = addressForNonce(2);
    address tokenPrecalculated = addressForNonce(3);
    address airgrabPrecalculated = addressForNonce(4);
    address lockingPrecalculated = addressForNonce(6);
    address governanceTimelockPrecalculated = addressForNonce(8);
    address governorPrecalculated = addressForNonce(10);
    address mentoLabsTreasuryPrecalculated = addressForNonce(11);

    address[] memory owners = new address[](1);
    owners[0] = governanceTimelockPrecalculated;

    // =========================================
    // ========== Deploy 1: ProxyAdmin =========
    // =========================================
    proxyAdmin = ProxyDeployerLib.deployAdmin(); // NONCE:1

    // =========================================
    // ========== Deploy 2: Emission ===========
    // =========================================
    emission = EmissionDeployerLib.deploy(tokenPrecalculated, mentoLabsTreasuryPrecalculated); // NONCE:2
    assert(address(emission) == emissionPrecalculated);

    // ===========================================
    // ========== Deploy 3: MentoToken ===========
    // ===========================================
    mentoToken = MentoTokenDeployerLib.deploy( // NONCE:3
      mentoLabsMultiSig,
      mentoLabsTreasuryPrecalculated,
      airgrabPrecalculated,
      governanceTimelockPrecalculated,
      address(emission)
    );
    assert(address(mentoToken) == tokenPrecalculated);

    // ========================================
    // ========== Deploy 4: Airgrab ===========
    // ========================================
    uint256 airgrabEnds = block.timestamp + AIRGRAB_DURATION;
    airgrab = AirgrabDeployerLib.deploy( // NONCE:4
      airgrabRoot,
      fractalSigner,
      FRACTAL_MAX_AGE,
      airgrabEnds,
      AIRGRAB_LOCK_CLIFF,
      AIRGRAB_LOCK_SLOPE,
      tokenPrecalculated,
      lockingPrecalculated,
      payable(communityFund)
    );
    assert(address(airgrab) == airgrabPrecalculated);

    // ==========================================
    // ========== Deploy 5-6: Locking ===========
    // ==========================================
    Locking lockingImpl = LockingDeployerLib.deploy(); // NONCE:5
    uint32 startingPointWeek = uint32(Locking(lockingImpl).getWeek() - 1);
    TransparentUpgradeableProxy lockingProxy = ProxyDeployerLib.deployProxy( // NONCE:6
      address(lockingImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        lockingImpl.__Locking_init.selector,
        address(mentoToken), /// @param _token The token to be locked in exchange for voting power in form of veTokens.
        startingPointWeek, ///   @param _startingPointWeek The locking epoch start in weeks. We start the locking contract from week 1 with min slope duration of 1
        0, ///                   @param _minCliffPeriod minimum cliff period in weeks.
        1 ///                    @param _minSlopPeriod minimum slope period in weeks.
      )
    );
    locking = Locking(address(lockingProxy));
    assert(address(locking) == lockingPrecalculated);

    // ===================================================================
    // ========== Deploy 7: Timelock Controller Implementation ===========
    // ===================================================================
    /// @dev This implementation will be reused for both the Governance Timelock and the Mento Labs Treasury Timelock
    TimelockController timelockControllerImpl = TimelockControllerDeployerLib.deploy(); // NONCE:7

    // ====================================================
    // ========== Deploy 8: Governance Timelock ===========
    // ====================================================
    address[] memory governanceProposers = new address[](1);
    address[] memory governanceExecutors = new address[](1);
    governanceProposers[0] = governorPrecalculated; // Only MentoGovernor can propose
    governanceExecutors[0] = address(0); // Anyone can execute passed proposals

    TransparentUpgradeableProxy governanceTimelockProxy = ProxyDeployerLib.deployProxy( // NONCE:8
      address(timelockControllerImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        timelockControllerImpl.__MentoTimelockController_init.selector,
        GOVERNANCE_TIMELOCK_DELAY, /// @param minDelay The minimum delay before a proposal can be executed.
        governanceProposers, ///       @param proposers List of addresses that are allowed to queue AND cancel operations.
        governanceExecutors, ///       @param executors List of addresses that are allowed to execute proposals.
        address(0), ///                @param admin No admin necessary as proposers are preset upon deployment.
        watchdogMultiSig ///           @param canceller An additional canceller address with the rights to cancel awaiting proposals.
      )
    );
    governanceTimelock = TimelockController(payable(governanceTimelockProxy));
    assert(address(governanceTimelock) == governanceTimelockPrecalculated);

    // ==================================================
    // ========== Deploy 9-10: Mento Governor ===========
    // ==================================================
    MentoGovernor mentoGovernorImpl = MentoGovernorDeployerLib.deploy(); // NONCE:9
    TransparentUpgradeableProxy mentoGovernorProxy = ProxyDeployerLib.deployProxy( // NONCE: 10
      address(mentoGovernorImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        mentoGovernorImpl.__MentoGovernor_init.selector,
        address(lockingProxy), ///       @param veToken The escrowed Mento Token used for voting.
        governanceTimelockProxy, ///     @param timelockController The timelock controller used by the governor.
        GOVERNOR_VOTING_DELAY, ///       @param votingDelay_ The delay time in blocks between the proposal creation and the start of voting.
        GOVERNOR_VOTING_PERIOD, ///      @param votingPeriod_ The voting duration in blocks between the vote start and vote end.
        GOVERNOR_PROPOSAL_THRESHOLD, /// @param threshold_ The number of votes required in order for a voter to become a proposer.
        GOVERNOR_QUORUM ///              @param quorum_ The minimum number of votes in percent of total supply required in order for a proposal to succeed.
      )
    );
    mentoGovernor = MentoGovernor(payable(mentoGovernorProxy));

    // ========================================================
    // =========== Deploy 11: Mento Labs Treasury =============
    // ========================================================
    address[] memory treasuryProposers = new address[](1);
    address[] memory treasuryExecutors = new address[](1);
    treasuryProposers[0] = address(mentoLabsMultiSig); // Only Mento Labs team can propose
    treasuryExecutors[0] = address(0); // Anyone can execute

    TransparentUpgradeableProxy mentoLabsTreasuryTimelockProxy = ProxyDeployerLib.deployProxy( // NONCE:11
      address(timelockControllerImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        timelockControllerImpl.__MentoTimelockController_init.selector,
        MENTOLABS_TREASURY_TIMELOCK_DELAY, /// @param minDelay The minimum delay before a proposal can be executed.
        treasuryProposers, ///                 @param proposers List of addresses that are allowed to queue and cancel operations.
        treasuryExecutors, ///                 @param executors List of addresses that are allowed to execute proposals. 0 can be used to allow any account.
        address(0), ///                        @param admin No admin necessary as proposers are preset upon deployment.
        governanceTimelock ///                 @param canceller An additional canceller address with the rights to cancel awaiting proposals.
      )
    );
    mentoLabsTreasuryTimelock = TimelockController(payable(mentoLabsTreasuryTimelockProxy));

    // =============================================
    // =========== Configure Ownership =============
    // =============================================
    emission.transferOwnership(address(governanceTimelock));
    locking.transferOwnership(address(governanceTimelock));
    proxyAdmin.transferOwnership(address(governanceTimelock));

    emit GovernanceCreated(
      address(proxyAdmin),
      address(emission),
      address(mentoToken),
      address(airgrab),
      address(locking),
      address(governanceTimelock),
      address(mentoGovernor),
      address(mentoLabsTreasuryTimelock),
      mentoLabsMultiSig
    );
  }

  /**
   * @notice Calculates a deterministic address based on a given nonce.
   * @param nonce The nonce used to generate the address.
   * @return The generated address.
   */
  function addressForNonce(uint256 nonce) internal view returns (address) {
    return
      address(
        uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(this), bytes1(uint8(nonce))))))
      );
  }
}
