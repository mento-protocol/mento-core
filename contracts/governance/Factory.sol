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

import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";

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

  ProxyAdmin public proxyAdmin;
  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;
  Locking public locking;
  address public treasury;

  address public mentolabsVestingMultisig;
  address public mentolabsTreasuryMultisig;
  address public watchdogMultisig;

  bool public initialized; // Indicates if the governance system has been created

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
  /// @param mentolabsVestingMultisig_ Address of the multisig from where current allocation will be vested
  /// @param watchdogMultisig_ Address of the community's multisig wallet with the veto rights
  /// @param airgrabRoot Root hash for the airgrab Merkle tree
  /// @param fractalSigner Signer of fractal kyc
  /// @dev This can only be called by the owner and only once
  function createGovernance(
    address mentolabsVestingMultisig_,
    address watchdogMultisig_,
    bytes32 airgrabRoot,
    address fractalSigner
  ) external onlyOwner {
    require(!initialized, "Factory: governance already created");
    initialized = true;

    mentolabsVestingMultisig = mentolabsVestingMultisig_;
    watchdogMultisig = watchdogMultisig_;

    // Precalculatedd conract addresses:
    address emissionPrecalculated = addressForNonce(2);
    address airgrabPrecalculated = addressForNonce(3);
    address tokenPrecalculated = addressForNonce(4);
    address lockingPrecalculated = addressForNonce(5);
    address payable treasuryPrecalculated = payable(address(1)); // TODO: replace with gnosis safe proxy usage
    address mentolabsTreasuryPrecalculated = address(2); // TODO replace with gnosis safe proxy usage

    // ========== Deploy: ProxyAdmin =========
    proxyAdmin = new ProxyAdmin(); // NONCE:1

    // ========== Deploy: Emission ===========
    emission = EmissionDeployerLib.deploy(tokenPrecalculated, treasuryPrecalculated); // NONCE:2
    require(address(emission) == emissionPrecalculated, "Factory: emission address mismatch");

    // ========== Deploy: Airgrab ===========
    uint256 airgrabEnds = block.timestamp + AIRGRAB_DURATION;
    airgrab = AirgrabDeployerLib.deploy( // NONCE:3
      airgrabRoot,
      fractalSigner,
      FRACTAL_MAX_AGE,
      airgrabEnds,
      AIRGRAB_LOCK_CLIFF,
      AIRGRAB_LOCK_SLOPE,
      tokenPrecalculated, 
      lockingPrecalculated, 
      treasuryPrecalculated
    );
    require(address(airgrab) == airgrabPrecalculated, "Factory: airgrab address mismatch");

    // ========== Deploy: MentoToken ===========
    mentoToken = MentoTokenDeployerLib.deploy( // NONCE:4
      mentolabsVestingMultisig,
      mentolabsTreasuryPrecalculated,
      address(airgrab), 
      treasuryPrecalculated, 
      address(emission)
    );
    require(address(mentoToken) == tokenPrecalculated, "Factory: token address mismatch");

    // ========== Deploy: Locking ===========
    Locking lockingImpl = LockingDeployerLib.deploy(); // NONCE:5
    TransparentUpgradeableProxy lockingProxy = new TransparentUpgradeableProxy(// NONCE:6
      address(lockingImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        lockingImpl.__Locking_init.selector,
        address(mentoToken),
        // we start the locking contract from week 1 with min slope duration of 1
        uint32(Locking(lockingImpl).getWeek() - 1),
        0,
        1
      )
    );
    locking = Locking(address(lockingProxy));
    require(address(locking) == lockingPrecalculated, "Factory: locking address mismatch");

    // ========== Deploy: TimelockController ===========
    TimelockController timelockControllerImpl = TimelockControllerDeployerLib.deploy(); // NONCE:7
    address[] memory proposers = new address[](1);
    address[] memory executors = new address[](1);
    proposers[0] = address(addressForNonce(10)); // Governor can propose and cancel
    executors[0] = address(0); // Anyone can execute

    TransparentUpgradeableProxy timelockControllerProxy = new TransparentUpgradeableProxy(// NONCE:8
      address(timelockControllerImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        timelockControllerImpl.__MentoTimelockController_init.selector,
        TIMELOCK_DELAY,
        proposers,
        executors,
        address(0), // no admin, other roles are preset
        watchdogMultisig
      )
    );
    timelockController = TimelockController(payable(timelockControllerProxy));

    // ========== Deploy: MentoGovernor ===========
    MentoGovernor mentoGovernorImpl = MentoGovernorDeployerLib.deploy(); // NONCE:9
    TransparentUpgradeableProxy mentoGovernorProxy = new TransparentUpgradeableProxy( // NONCE: 10
      address(mentoGovernorImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        mentoGovernorImpl.__MentoGovernor_init.selector,
        IVotesUpgradeable(address(lockingProxy)),
        timelockControllerProxy,
        GOVERNOR_VOTING_DELAY,
        GOVERNOR_VOTING_PERIOD,
        GOVERNOR_PROPOSAL_THRESHOLD,
        GOVERNOR_QUORUM
      )
    );
    mentoGovernor = MentoGovernor(payable(mentoGovernorProxy));

    // =========== Deploy: Mento Treasury =============
    // TODO

    // =========== Deploy: MentoLabs Treasury =============
    // TODO

    // ============= Configure ownership ================
    emission.transferOwnership(address(timelockController));
    locking.transferOwnership(address(timelockController));

    emit GovernanceCreated(
      address(mentoToken),
      address(emission),
      address(airgrab),
      mentolabsTreasuryMultisig,
      mentolabsVestingMultisig,
      treasuryPrecalculated,
      address(locking),
      address(timelockController),
      address(mentoGovernor)
    );
  }

  function addressForNonce(uint256 nonce) internal view returns (address) {
    return address(
      uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), address(this), bytes1(uint8(nonce))))))
    );
  }
}
