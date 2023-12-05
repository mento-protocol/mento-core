// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { console2 } from "forge-std/console2.sol";
import { TestSetup } from "./TestSetup.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { MockGnosisSafeProxyFactory } from "../mocks/MockGnosisSafeProxyFactory.sol";

contract GovernanceFactoryTest is TestSetup {
  GovernanceFactory public factory;
  MockGnosisSafeProxyFactory public gnosisSafeProxyFactory;

  address public communityMultisig = makeAddr("CommunityMultisig");
  address public mentolabsVestingMultisig = makeAddr("MentoLabsVestingMultisig");
  address public treasuryContract = makeAddr("TreasuryContract");
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public airgrabMerkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809; // Mock root

  // TODO: Document why this is necessary
  // If we take this out, there'll be underflow errors, supposedly linked to some signature being valid only at a certain time and requiring some buffer
  function setUp() public {
    skip(30 days);
    vm.roll(30 * BLOCKS_DAY);
  }

  function _newFactory() internal {
    factory = new GovernanceFactory(owner, address(0), address(gnosisSafeProxyFactory));
  }

  function _newMockGnosisSafeProxyFactory() internal {
    gnosisSafeProxyFactory = new MockGnosisSafeProxyFactory();
  }

  function _createGovernance() internal {
    factory.createGovernance(mentolabsVestingMultisig, communityMultisig, airgrabMerkleRoot, fractalSigner);
  }

  // ========================================
  // GovernanceFactory.constructor
  // ========================================
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  function test_constructor_transfersOwnership() public {
    vm.prank(alice);
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(alice, owner);

    _newFactory();

    assertEq(address(factory.owner()), owner);
  }

  // Can't test gnosisSafeProxyFactory state variable because it's private
  // function test_constructor_setsGnosisSafeProxyFactory() public { }

  // Can't test gnosisSafeSingleton state variable because it's private
  // function test_constructor_setsGnosisSafeSingleton() public { }

  // ========================================
  // GovernanceFactory.createGovernance
  // ========================================
  /// @notice setup for initialize tests
  modifier i_setUp() {
    _newMockGnosisSafeProxyFactory();
    _newFactory();
    _;
  }

  //
  // ✅ Positive Tests
  //

  function test_createGovernance_whenCallerOwner_shouldDeployAllGovernanceContracts() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    // Check that the contracts have been deployed
    assertFalse(address(factory.proxyAdmin()) == address(0), "ProxyAdmin not deployed");
    assertFalse(address(factory.emission()) == address(0), "Emission not deployed");
    assertFalse(address(factory.mentoToken()) == address(0), "MentoToken not deployed");
    assertFalse(address(factory.airgrab()) == address(0), "Airgrab not deployed");
    assertFalse(address(factory.locking()) == address(0), "Locking not deployed");
    assertFalse(address(factory.timelockController()) == address(0), "TimelockController not deployed");
    assertFalse(address(factory.mentoGovernor()) == address(0), "MentoGovernor not deployed");
    assertFalse(address(factory.treasury()) == address(0), "Treasury not deployed");
    assertFalse(address(factory.mentolabsTreasury()) == address(0), "Mento Labs Treasury not deployed");
  }

  function test_createGovernance_whenCallerOwner_shouldDeployEmissionWithCorrectConfig() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    assertEq(
      address(factory.emission().mentoToken()),
      address(factory.mentoToken()),
      "Emission: Incorrect Mento token address"
    );
    assertEq(factory.emission().emissionTarget(), treasuryContract, "Emission: Incorrect emission target address");
  }

  function test_createGovernance_whenCallerOwner_shouldDeployTokenWithCorrectConfig() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    uint256 totalSupply = 1_000_000_000 * 10**18;
    uint256 emissionSupply = (totalSupply * 65) / 100;
    uint256 totalSupplyLessEmissions = totalSupply - emissionSupply;

    uint256 vestingSupply = (totalSupply * 8) / 100;
    uint256 mentolabsTreasurySupply = (totalSupply * 12) / 100;
    uint256 airgrabSupply = (totalSupply * 5) / 100;
    uint256 treasurySupply = (totalSupply * 10) / 100;

    assertEq(factory.mentoToken().symbol(), "MENTO", "MentoToken: Incorect token symbol");
    assertEq(factory.mentoToken().name(), "Mento Token", "MentoToken: Incorrect token name");
    assertEq(factory.mentoToken().totalSupply(), totalSupplyLessEmissions, "MentoToken: Incorrect total supply");

    assertEq(
      factory.mentoToken().balanceOf(mentolabsVestingMultisig),
      vestingSupply,
      "MentoToken: Incorrect vesting balance"
    );
    assertEq(
      factory.mentoToken().balanceOf(address(factory.mentolabsTreasury())),
      mentolabsTreasurySupply,
      "MentoToken: Incorrect Mento Labs treasury balance"
    );
    assertEq(
      factory.mentoToken().balanceOf(address(factory.airgrab())),
      airgrabSupply,
      "MentoToken: Incorrect airgrab balance"
    );
    assertEq(
      factory.mentoToken().balanceOf(treasuryContract),
      treasurySupply,
      "MentoToken: Incorrect treasury balance"
    );
  }

  function test_createGovernance_whenCallerOwner_shouldDeployAirgrabWithCorrectConfig() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    assertEq(factory.airgrab().root(), airgrabMerkleRoot, "Airgrab: Incorrect merkel root");
    assertEq(factory.airgrab().fractalSigner(), fractalSigner, "Airgrab: Incorrect fractal signer");
    assertEq(factory.airgrab().fractalMaxAge(), factory.FRACTAL_MAX_AGE(), "Airgrab: Incorrect fractal max age");
    assertEq(
      factory.airgrab().endTimestamp(),
      block.timestamp + factory.AIRGRAB_DURATION(),
      "Airgrab: Incorrect end time"
    );
    assertEq(factory.airgrab().cliffPeriod(), factory.AIRGRAB_LOCK_CLIFF(), "Airgrab: Incorrect lock cliff");
    assertEq(factory.airgrab().slopePeriod(), factory.AIRGRAB_LOCK_SLOPE(), "Airgrab: Incorrect lock slope");
    assertEq(
      address(factory.airgrab().token()),
      address(factory.mentoToken()),
      "Airgrab: Incorrect mento token address"
    );
    assertEq(address(factory.airgrab().locking()), address(factory.locking()), "Airgrab: Incorrect locking address");
    assertEq(address(factory.airgrab().treasury()), address(factory.treasury()), "Airgrab: Incorrect treasury address");
  }

  function test_createGovernance_whenCallerOwner_shouldDeployLockingWithCorrectConfig() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    assertEq(factory.locking().symbol(), "veMENTO", "Locking: Incorrect lock token symbol");
    assertEq(factory.locking().name(), "Mento Vote-Escrow", "Locking: Incorrect lock token name");
    assertEq(factory.locking().decimals(), 18, "Locking: Incorrect lock token decimals");

    assertEq(
      address(factory.locking().token()),
      address(factory.mentoToken()),
      "Locking: Incorrect mento token address"
    );

    assertEq(
      factory.locking().startingPointWeek(),
      3,
      "Locking: Incorrect starting point week. Should be Wednesday (3rd day of the week)."
    );
    assertEq(factory.locking().minCliffPeriod(), 0, "Locking: Incorrect min cliff period");
    assertEq(factory.locking().minSlopePeriod(), 1, "Locking: Incorrect min slope period");
  }

  function test_createGovernance_whenCallerOwner_shouldDeployTimelockControllerWithCorrectConfig() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    assertEq(
      factory.timelockController().getMinDelay(),
      factory.GOVERNANCE_TIMELOCK_DELAY(),
      "Timelock: Incorrect min delay"
    );

    bytes32 proposerRole = factory.timelockController().PROPOSER_ROLE();
    bytes32 executorRole = factory.timelockController().EXECUTOR_ROLE();
    bytes32 cancellerRole = factory.timelockController().CANCELLER_ROLE();

    assertTrue(
      factory.timelockController().hasRole(proposerRole, address(factory.mentoGovernor())),
      "Timelock: Mento Governor should have proposer role"
    );
    assertTrue(
      factory.timelockController().hasRole(executorRole, address(0)),
      "Timelock: Anyone should be able to execute approved proposals"
    );
    assertTrue(
      factory.timelockController().hasRole(cancellerRole, factory.watchdogMultisig()),
      "Timelock: Watchdog community multisig should have canceller role"
    );
  }

  function test_createGovernance_shouldSetOwners() public i_setUp {
    vm.prank(owner);
    _createGovernance();
    address timelock = address(factory.timelockController());
    assertEq(factory.emission().owner(), timelock);
    assertEq(factory.locking().owner(), timelock);
  }

  //
  // ❌ Negative Tests
  //
  function test_createGovernance_whenCallerNotOwner_shouldRevert() public i_setUp {
    vm.expectRevert("Ownable: caller is not the owner");
    _createGovernance();
  }

  function test_createGovernance_whenCalledTwice_shouldRevert() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    vm.prank(owner);
    vm.expectRevert("Factory: governance already created");
    _createGovernance();
  }
}
