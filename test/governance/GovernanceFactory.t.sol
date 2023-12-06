// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { TestSetup } from "./TestSetup.sol";
import { TestLocking } from "../utils/TestLocking.sol";
import { MockGnosisSafeProxyFactory } from "../mocks/MockGnosisSafeProxyFactory.sol";

import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";

// solhint-disable-next-line max-line-length
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { GovernanceFactoryHarness } from "./GovernanceFactoryHarness.t.sol";
import { IGnosisSafe } from "contracts/governance/interfaces/IGnosisSafe.sol";
import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";

contract GovernanceFactoryTest is TestSetup {
  GovernanceFactoryHarness public factory;
  MockGnosisSafeProxyFactory public gnosisSafeProxyFactory;

  address public communityMultisig = makeAddr("CommunityMultisig");
  address public mentolabsVestingMultisig = makeAddr("MentoLabsVestingMultisig");
  address public treasuryContract = makeAddr("TreasuryContract");
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public airgrabMerkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809; // Mock root

  // TODO: Document why this is necessary
  // If we take this out, there'll be underflow errors, supposedly linked to some signature being
  // valid only at a certain time and requiring some buffer
  function setUp() public {
    skip(30 days);
    vm.roll(30 * BLOCKS_DAY);
  }

  function _newFactory() internal {
    factory = new GovernanceFactoryHarness(owner, address(0), address(gnosisSafeProxyFactory));
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

  function test_createGovernance_shouldTransferOwnershipToTimelockController() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    address timelock = address(factory.timelockController());
    assertEq(factory.emission().owner(), timelock);
    assertEq(factory.locking().owner(), timelock);
    assertEq(factory.proxyAdmin().owner(), timelock);
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

  // ========================================
  // Upgradeability Test: Locking
  // ========================================
  function test_createGovernance_upgradeable_lockingShouldBeUpgradeable() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    ProxyAdmin proxyAdmin = factory.proxyAdmin();
    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(factory.locking()));

    assertEq(
      proxyAdmin.getProxyAdmin(proxy),
      address(factory.proxyAdmin()),
      "Factory: lockingProxy should have a proxyAdmin"
    );

    // we can cheat and calculate the address of the implementation contract via addressForNonce()
    address precalculatedAddress = factory.exposed_addressForNonce(5);
    address initialImpl = proxyAdmin.getProxyImplementation(proxy);
    assertEq(initialImpl, precalculatedAddress, "Factory: lockingProxy should have an implementation");

    // deploy and upgrade to new implementation
    TestLocking newImplContract = new TestLocking();
    vm.prank(address(factory.timelockController()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: LockingProxy should have a new implementation");
  }

  // ========================================
  // Upgradeability Test: TimelockController
  // ========================================
  function test_createGovernance_upgradeable_timelockControllerShouldBeUpgradeable() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    ProxyAdmin proxyAdmin = factory.proxyAdmin();
    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(factory.timelockController()));

    assertEq(
      proxyAdmin.getProxyAdmin(proxy),
      address(factory.proxyAdmin()),
      "Factory: timelockControllerProxy should have a proxyAdmin"
    );

    // we can cheat and calculate the address of the implementation contract via addressForNonce()
    address precalculatedAddress = factory.exposed_addressForNonce(7);
    address initialImpl = proxyAdmin.getProxyImplementation(proxy);
    assertEq(initialImpl, precalculatedAddress, "Factory: timelockControllerProxy should have an implementation");

    // deploy and upgrade to new implementation
    TimelockController newImplContract = new TimelockController();
    vm.prank(address(factory.timelockController()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: timelockControllerProxy should have a new implementation");
  }

  // ==================================
  // Upgradeability Test: MentoGovernor
  // ==================================
  function test_createGovernance_upgradeable_mentoGovernorShouldBeUpgradeable() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    ProxyAdmin proxyAdmin = factory.proxyAdmin();
    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(factory.mentoGovernor()));

    assertEq(
      proxyAdmin.getProxyAdmin(proxy),
      address(factory.proxyAdmin()),
      "Factory: mentoGovernorProxy should have a proxyAdmin"
    );

    // we can cheat and calculate the address of the implementation contract via addressForNonce()
    address precalculatedAddress = factory.exposed_addressForNonce(9);
    address initialImpl = proxyAdmin.getProxyImplementation(proxy);
    assertEq(initialImpl, precalculatedAddress, "Factory: mentoGovernorProxy should have an implementation");

    // deploy and upgrade to new implementation
    MentoGovernor newImplContract = new MentoGovernor();
    vm.prank(address(factory.timelockController()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: mentoGovernorProxy should have a new implementation");
  }

  // ========================================
  // Upgradeability Test: Mento Labs Treasury
  // ========================================
  function test_createGovernance_upgradeable_mentoLabsTreasuryShouldBeUpgradeable() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    ProxyAdmin proxyAdmin = factory.proxyAdmin();
    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(factory.mentolabsTreasury()));

    assertEq(
      proxyAdmin.getProxyAdmin(proxy),
      address(factory.proxyAdmin()),
      "Factory: mentolabsTreasuryProxy should have a proxyAdmin"
    );

    // we can cheat and calculate the address of the implementation contract via addressForNonce()
    address precalculatedAddress = factory.exposed_addressForNonce(7);
    address initialImpl = proxyAdmin.getProxyImplementation(proxy);
    assertEq(initialImpl, precalculatedAddress, "Factory: mentolabsTreasuryProxy should have an implementation");

    // deploy and upgrade to new implementation
    TimelockController newImplContract = new TimelockController();
    vm.prank(address(factory.timelockController()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: mentolabsTreasuryProxy should have a new implementation");
  }

  // ========================================
  // Upgradeability Test: Immutable Contracts
  // ========================================
  function test_createGovernance_upgradeable_otherContractsShouldBeImmutable() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    ProxyAdmin proxyAdmin = factory.proxyAdmin();

    ITransparentUpgradeableProxy emissionNotAProxy = ITransparentUpgradeableProxy(address(factory.emission()));
    vm.expectRevert();
    proxyAdmin.getProxyAdmin(emissionNotAProxy);

    ITransparentUpgradeableProxy mentoTokenNotAProxy = ITransparentUpgradeableProxy(address(factory.mentoToken()));
    vm.expectRevert();
    proxyAdmin.getProxyAdmin(mentoTokenNotAProxy);

    ITransparentUpgradeableProxy airgrabNotAProxy = ITransparentUpgradeableProxy(address(factory.airgrab()));
    vm.expectRevert();
    proxyAdmin.getProxyAdmin(airgrabNotAProxy);

    ITransparentUpgradeableProxy treasuryNotAProxy = ITransparentUpgradeableProxy(address(factory.treasury()));
    vm.expectRevert();
    proxyAdmin.getProxyAdmin(treasuryNotAProxy);
  }

  // ===========================================
  // GovernanceFactory.calculateSafeProxyAddress
  // ===========================================
  function test_calculateSafeProxyAddress() public i_setUp {
    vm.prank(owner);
    _createGovernance();
    address[] memory owners = new address[](1);
    bytes memory treasuryInitializer = abi.encodeWithSelector(
      IGnosisSafe.setup.selector,
      owners,
      1,
      address(0),
      "",
      address(0),
      address(0),
      0,
      address(0)
    );

    uint256 saltNonce = uint256(keccak256(abi.encodePacked("mentolabsTreasury")));
    address result = factory.exposed_calculateSafeProxyAddress(treasuryInitializer, saltNonce);
    assertEq(factory.treasury(), result, "calculateSafeProxyAddress: Should return correct address");
  }

  // ==================================
  // GovernanceFactory.addressForNonce
  // ==================================
  function testFuzz_addressForNonce_whenNoncesAreIdentical_shouldReturnTheSameAddress(uint256 nonce) public i_setUp {
    address account0 = factory.exposed_addressForNonce(nonce);
    address account1 = factory.exposed_addressForNonce(nonce);
    assertTrue(account0 == account1, "addressForNonce: Should return same address for same nonce");
  }

  function testFuzz_addressForNonce_whenNoncesAreDifferent_shouldReturnDifferentAddresses(uint256 nonce)
    public
    i_setUp
  {
    // We can only safely get 256 unique addresses because we're using
    // a uint8 nonce in the function `bytes1(uint8(nonce))`
    vm.assume(nonce > 0);
    vm.assume(nonce < 256);
    address account0 = factory.exposed_addressForNonce(0);
    address account1 = factory.exposed_addressForNonce(nonce);
    assertFalse(account0 == account1, "addressForNonce: Should return different addresses for different nonces");
  }

  // ================================
  // GovernanceFactory.bytesToAddress
  // ================================
  function test_bytesToAddress() public i_setUp {
    address expectedAddress = 0x742d35Cc6634C0532925a3b844Bc454e4438f44e;
    bytes memory data = abi.encodePacked(expectedAddress);
    assertEq(factory.exposed_bytesToAddress(data), expectedAddress, "bytesToAddress: Should return correct address");
  }
}
