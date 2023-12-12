// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { MentoToken } from "./MentoToken.sol";
import { Emission } from "./Emission.sol";
import { Airgrab } from "./Airgrab.sol";
import { TimelockController } from "./TimelockController.sol";
import { MentoGovernor } from "./MentoGovernor.sol";
import { Locking } from "./locking/Locking.sol";
import { GnosisSafeProxyFactory } from "safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import { GnosisSafeProxy } from "safe-contracts/proxies/GnosisSafeProxy.sol";
import { GnosisSafe } from "safe-contracts/GnosisSafe.sol";

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
    address mentoToken,
    address emission,
    address airgrab,
    address mentolabsTreasury,
    address mentolabsMultisig,
    address treasury,
    address locking,
    address timelock,
    address governor
  );

  GnosisSafeProxyFactory private gnosisSafeProxyFactory;
  address private gnosisSafeSingleton;

  ProxyAdmin public proxyAdmin;
  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  TimelockController public timelockController;
  MentoGovernor public mentoGovernor;
  Locking public locking;
  GnosisSafeProxy public treasury;
  TimelockController public mentolabsTreasury;

  address public mentolabsVestingMultisig;
  address public watchdogMultisig;

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
  uint256 public constant GOVERNOR_VOTING_DELAY = 1; // Voting start the next block
  uint256 public constant GOVERNOR_VOTING_PERIOD = 120_960; // Voting period for the governor (7 days in blocks CELO)
  uint256 public constant GOVERNOR_PROPOSAL_THRESHOLD = 1_000e18;
  uint256 public constant GOVERNOR_QUORUM = 2; // Quorum percentage for the governor

  // MentoLabs Treasury Timelock configuration
  // TODO: Discuss value, 7 days (gov) + 2 days (gov timelock) + 2 days? (buffer)
  uint256 public constant MENTOLABS_TREASURY_TIMELOCK_DELAY = 11 days;

  /// @notice Creates the factory with the owner address
  /// @param owner_ Address of the owner, Celo governance
  /// @param gnosisSafeSingleton_ Address of the Gnosis Safe singleton
  /// @param gnosisSafeProxyFactory_ Address of the Gnosis Safe proxy factory
  constructor(
    address owner_,
    address gnosisSafeSingleton_,
    address gnosisSafeProxyFactory_
  ) {
    transferOwnership(owner_);
    gnosisSafeSingleton = gnosisSafeSingleton_;
    gnosisSafeProxyFactory = GnosisSafeProxyFactory(gnosisSafeProxyFactory_);
  }

  /// @notice Creates and initializes the governance system contracts
  /// @param mentolabsVestingMultisig_ Address of the multisig from where current allocation will be vested
  /// @param watchdogMultisig_ Address of the community's multisig wallet with the veto rights
  /// @param airgrabRoot Root hash for the airgrab Merkle tree
  /// @param fractalSigner Signer of fractal kyc
  /// @dev This can only be called by the owner and only once
  // solhint-disable-next-line function-max-lines
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

    // Precalculated contract addresses:
    address emissionPrecalculated = addressForNonce(2);
    address tokenPrecalculated = addressForNonce(3);
    address airgrabPrecalculated = addressForNonce(4);
    address lockingPrecalculated = addressForNonce(6);
    address governanceTimelockPrecalculated = addressForNonce(8);
    address governorPrecalculated = addressForNonce(10);
    address mentolabsTreasuryPrecalculated = addressForNonce(11);

    address[] memory owners = new address[](1);
    owners[0] = governanceTimelockPrecalculated;

    // Encoded arguments for Gnosis Safe's setup() function
    // https://github.com/safe-global/safe-contracts/blob/v1.3.0/contracts/GnosisSafe.sol#L66-L97
    bytes memory treasuryInitializer = abi.encodeWithSelector(
      GnosisSafe.setup.selector,
      owners, ///     @param _owners List of Safe owners.
      1, ///          @param _threshold Number of required confirmations for a Safe transaction.
      address(0), /// @param to Contract address for optional delegate call.
      "", ///         @param data Data payload for optional delegate call.
      address(0), /// @param fallbackHandler Handler for fallback calls to this contract
      address(0), /// @param paymentToken Token that should be used for the payment (0 is ETH)
      0, ///          @param payment Value that should be paid
      address(0) ///  @param paymentReceiver Adddress that should receive the payment (or 0 if tx.origin)
    );
    uint256 treasurySalt = uint256(keccak256(abi.encodePacked("mentolabsTreasury")));
    address payable treasuryPrecalculated = payable(calculateSafeProxyAddress(treasuryInitializer, treasurySalt));

    // =======================================
    // ========== Deploy: ProxyAdmin =========
    // =======================================
    proxyAdmin = ProxyDeployerLib.deployAdmin(); // NONCE:1

    // =======================================
    // ========== Deploy: Emission ===========
    // =======================================
    emission = EmissionDeployerLib.deploy(tokenPrecalculated, treasuryPrecalculated); // NONCE:2
    assert(address(emission) == emissionPrecalculated);

    // =========================================
    // ========== Deploy: MentoToken ===========
    // =========================================
    mentoToken = MentoTokenDeployerLib.deploy( // NONCE:3
      mentolabsVestingMultisig,
      mentolabsTreasuryPrecalculated,
      airgrabPrecalculated,
      treasuryPrecalculated,
      address(emission)
    );

    assert(address(mentoToken) == tokenPrecalculated);

    // ======================================
    // ========== Deploy: Airgrab ===========
    // ======================================
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
      treasuryPrecalculated
    );
    assert(address(airgrab) == airgrabPrecalculated);

    // ======================================
    // ========== Deploy: Locking ===========
    // ======================================
    Locking lockingImpl = LockingDeployerLib.deploy(); // NONCE:5
    TransparentUpgradeableProxy lockingProxy = ProxyDeployerLib.deployProxy( // NONCE:6
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
    assert(address(locking) == lockingPrecalculated);

    // =================================================
    // ========== Deploy: TimelockController ===========
    // =================================================
    TimelockController timelockControllerImpl = TimelockControllerDeployerLib.deploy(); // NONCE:7
    address[] memory proposers = new address[](1);
    address[] memory executors = new address[](1);
    proposers[0] = governorPrecalculated; // Governor can propose and cancel
    executors[0] = address(0); // Anyone can execute

    TransparentUpgradeableProxy timelockControllerProxy = ProxyDeployerLib.deployProxy( // NONCE:8
      address(timelockControllerImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        timelockControllerImpl.__MentoTimelockController_init.selector,
        GOVERNANCE_TIMELOCK_DELAY,
        proposers,
        executors,
        address(0), // no admin, other roles are preset
        watchdogMultisig
      )
    );
    timelockController = TimelockController(payable(timelockControllerProxy));
    assert(address(timelockController) == governanceTimelockPrecalculated);

    // ============================================
    // ========== Deploy: MentoGovernor ===========
    // ============================================
    MentoGovernor mentoGovernorImpl = MentoGovernorDeployerLib.deploy(); // NONCE:9
    TransparentUpgradeableProxy mentoGovernorProxy = ProxyDeployerLib.deployProxy( // NONCE: 10
      address(mentoGovernorImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        mentoGovernorImpl.__MentoGovernor_init.selector,
        address(lockingProxy),
        timelockControllerProxy,
        GOVERNOR_VOTING_DELAY,
        GOVERNOR_VOTING_PERIOD,
        GOVERNOR_PROPOSAL_THRESHOLD,
        GOVERNOR_QUORUM
      )
    );
    mentoGovernor = MentoGovernor(payable(mentoGovernorProxy));

    // ================================================
    // =========== Deploy: Mento Treasury =============
    // ================================================
    treasury = gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafeSingleton, treasuryInitializer, treasurySalt);
    assert(address(treasury) == treasuryPrecalculated);

    // ====================================================
    // =========== Deploy: MentoLabs Treasury =============
    // ====================================================
    address[] memory treasuryProposers = new address[](1);
    address[] memory treasuryExecutors = new address[](1);
    proposers[0] = address(mentolabsVestingMultisig); // Governor can propose and cancel
    executors[0] = address(0); // Anyone can execute

    TransparentUpgradeableProxy mltreasuryTimelockControllerProxy = ProxyDeployerLib.deployProxy( // NONCE:11
      address(timelockControllerImpl),
      address(proxyAdmin),
      abi.encodeWithSelector(
        timelockControllerImpl.__MentoTimelockController_init.selector,
        MENTOLABS_TREASURY_TIMELOCK_DELAY,
        treasuryProposers,
        treasuryExecutors,
        address(0), // no admin, other roles are preset
        timelockController
      )
    );
    mentolabsTreasury = TimelockController(payable(mltreasuryTimelockControllerProxy));

    // ============= Configure ownership ================
    emission.transferOwnership(address(timelockController));
    locking.transferOwnership(address(timelockController));
    proxyAdmin.transferOwnership(address(timelockController));

    emit GovernanceCreated(
      address(mentoToken),
      address(emission),
      address(airgrab),
      address(mentolabsTreasury),
      mentolabsVestingMultisig,
      treasuryPrecalculated,
      address(locking),
      address(timelockController),
      address(mentoGovernor)
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

  /**
   * @notice Calculates the address of a Gnosis Safe proxy contract with a given initializer and salt nonce.
   * @dev Implementation for calculateCreateProxyWithNonceAddress can be found here:
   *      https://github.com/safe-global/safe-contracts/blob/v1.3.0/contracts/proxies/GnosisSafeProxyFactory.sol#L93-L106
   * @param initializer The initializer data for the proxy contract.
   * @param saltNonce The salt nonce used to calculate the address.
   * @return proxy The address of the Gnosis Safe proxy contract.
   */
  function calculateSafeProxyAddress(bytes memory initializer, uint256 saltNonce) internal returns (address proxy) {
    try gnosisSafeProxyFactory.calculateCreateProxyWithNonceAddress(gnosisSafeSingleton, initializer, saltNonce) {
      assert(false);
    } catch Error(string memory reason) {
      // `reason` will be the proxy address in string format which we can then convert to an address
      proxy = bytesToAddress(bytes(reason));
    }
  }

  /**
   * @notice Converts a bytes array to an address.
   * @param bys The bytes array to convert.
   * @return addr The converted address.
   */
  function bytesToAddress(bytes memory bys) private pure returns (address addr) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      addr := mload(add(bys, 20))
    }
  }
}
