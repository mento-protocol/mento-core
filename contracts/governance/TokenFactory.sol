// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable max-line-length

import { MentoToken } from "./MentoToken.sol";
import { Emission } from "./Emission.sol";
import { Airgrab } from "./Airgrab.sol";
import { Locking } from "./locking/Locking.sol";

import { Ownable } from "openzeppelin-contracts-next/contracts/access/Ownable.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";

/**
 * @title Token Factory
 * @author Mento Labs
 * @notice Factory for creating and initializing the token related contracts
 **/
contract TokenFactory is Ownable {
  /// @dev Event emitted when the token contracts are successfully created
  event TokenCreated(
    address mentoToken,
    address emission,
    address airgrab,
    address mentoMultisig,
    address vesting,
    address treasury,
    address locking
  );

  MentoToken public mentoToken;
  Emission public emission;
  Airgrab public airgrab;
  Locking public locking;

  bool public initialized; // Indicates if the  token has been created
  address public vesting;
  address public mentoMultisig;
  address public treasury;

  // Airgrab configuration
  uint32 public constant AIRGRAB_LOCK_SLOPE = 104; // Slope duration for the airgrabed tokens in weeks
  uint32 public constant AIRGRAB_LOCK_CLIFF = 0; // Cliff duration for the airgrabed tokens in weeks
  uint256 public constant AIRGRAB_DURATION = 365 days;
  uint256 public constant FRACTAL_MAX_AGE = 180 days; // Maximum age of the kyc for the airgrab

  /// @notice Creates the factory with the owner address
  /// @param owner_ Address of the owner, Celo governance
  constructor(address owner_) {
    transferOwnership(owner_);
  }

  /// @notice Creates and initializes the governance system contracts
  /// @param vesting_ Address of the vesting contract
  /// @param mentoMultisig_ Address of the mento multisig
  /// @param treasury_ Address of the treasury
  /// @param airgrabRoot Root hash for the airgrab Merkle tree
  /// @param fractalSigner Signer of fractal kyc
  /// @param lockingImplementation Address of the implementation of locking contract
  /// @dev This can only be called by the owner and only once
  function createTokenContracts(
    address vesting_,
    address mentoMultisig_,
    address treasury_,
    bytes32 airgrabRoot,
    address fractalSigner,
    address lockingImplementation
  ) external onlyOwner {
    require(!initialized, "TokenFactory: token already created");
    initialized = true;

    // ---------------------------------- //
    // TODO: Replace with actual contracts
    vesting = vesting_;
    treasury = treasury_;
    // ---------------------------------- //

    mentoMultisig = mentoMultisig_;

    TransparentUpgradeableProxy lockingProxy = new TransparentUpgradeableProxy(lockingImplementation, msg.sender, "");
    locking = Locking(address(lockingProxy));

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

    // Initializations
    airgrab.initialize(address(mentoToken), address(locking), treasury);
    emission.setTokenContract(address(mentoToken));
    emission.setEmissionTarget(treasury);
    // we start the locking contract from week 1 with min slope duration of 1
    locking.__Locking_init(IERC20Upgradeable(address(mentoToken)), uint32(locking.getWeek() - 1), 0, 1);

    // Ownerships will be transfered to the timelock in a later proposal
    emission.transferOwnership(msg.sender);
    locking.transferOwnership(msg.sender);

    emit TokenCreated(
      address(mentoToken),
      address(emission),
      address(airgrab),
      mentoMultisig,
      vesting,
      treasury,
      address(locking)
    );
  }
}
