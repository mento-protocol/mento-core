// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase, max-line-length

import { TestSetup } from "./TestSetup.sol";
import { TestLocking } from "../utils/TestLocking.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";
import { GovernanceFactoryHarness } from "./GovernanceFactoryHarness.t.sol";
import { MentoGovernor } from "contracts/governance/MentoGovernor.sol";
import { TimelockController } from "contracts/governance/TimelockController.sol";

contract GovernanceFactoryTest is TestSetup {
  GovernanceFactoryHarness public factory;

  address public mentoLabsMultiSig = makeAddr("MentoLabsVestingMultisig");
  address public watchdogMultiSig = makeAddr("CommunityMultisig");
  address public communityFund = makeAddr("CommunityFund");
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public airgrabMerkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809; // Mock root

  // If we started at block 0, Locking.getWeek() would return 0 and
  // the following line would revert with an underflow:
  // https://github.com/mento-protocol/mento-core/blob/2075c83f3b90465f988195dd746c9992614001bc/contracts/governance/GovernanceFactory.sol#L201
  function setUp() public {
    skip(30 days);
    vm.roll(30 * BLOCKS_DAY);
  }

  function _newFactory() internal {
    factory = new GovernanceFactoryHarness(owner);
  }

  function _createGovernance() internal {
    factory.createGovernance(mentoLabsMultiSig, watchdogMultiSig, communityFund, airgrabMerkleRoot, fractalSigner);
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

  // ========================================
  // GovernanceFactory.createGovernance
  // ========================================
  /// @notice setup for initialize tests
  modifier i_setUp() {
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
    assertFalse(address(factory.governanceTimelock()) == address(0), "TimelockController not deployed");
    assertFalse(address(factory.mentoGovernor()) == address(0), "MentoGovernor not deployed");
    assertFalse(address(factory.mentoLabsTreasuryTimelock()) == address(0), "Mento Labs Treasury not deployed");
  }

  function test_createGovernance_shouldTransferOwnershipToTimelockController() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    address timelock = address(factory.governanceTimelock());
    assertEq(factory.emission().owner(), timelock);
    assertEq(factory.locking().owner(), timelock);
    assertEq(factory.proxyAdmin().owner(), timelock);
  }

  //
  // ❌ Negative Tests
  //
  function test_createGovernance_whenCallerOwner_shouldNotDeployMoreContractsThanExpected() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    // Confirm that no more contracts than expected have been deployed
    uint256 nonce = vm.getNonce(address(factory));
    assertEq(nonce, 12);
  }

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
  function test_createGovernance_lockingShouldBeUpgradeable() public i_setUp {
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
    vm.prank(address(factory.governanceTimelock()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: LockingProxy should have a new implementation");
    assertTrue(newImpl == address(newImplContract), "Factory: LockingProxy implementation should equal newImpl");
  }

  // ========================================
  // Upgradeability Test: Governance Timelock
  // ========================================
  function test_createGovernance_governanceTimelockShouldBeUpgradeable() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    ProxyAdmin proxyAdmin = factory.proxyAdmin();
    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(factory.governanceTimelock()));

    assertEq(
      proxyAdmin.getProxyAdmin(proxy),
      address(factory.proxyAdmin()),
      "Factory: governanceTimelock should have a proxyAdmin"
    );

    // we can cheat and calculate the address of the implementation contract via addressForNonce()
    address precalculatedAddress = factory.exposed_addressForNonce(7);
    address initialImpl = proxyAdmin.getProxyImplementation(proxy);
    assertEq(initialImpl, precalculatedAddress, "Factory: governanceTimelockProxy should have an implementation");

    // deploy and upgrade to new implementation
    TimelockController newImplContract = new TimelockController();
    vm.prank(address(factory.governanceTimelock()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: governanceTimelockProxy should have a new implementation");
    assertTrue(
      newImpl == address(newImplContract),
      "Factory: governanceTimelockProxy implementation should equal newImpl"
    );
  }

  // ==================================
  // Upgradeability Test: MentoGovernor
  // ==================================
  function test_createGovernance_mentoGovernorShouldBeUpgradeable() public i_setUp {
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
    vm.prank(address(factory.governanceTimelock()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: mentoGovernorProxy should have a new implementation");
    assertTrue(newImpl == address(newImplContract), "Factory: mentoGovernorProxy implementation should equal newImpl");
  }

  // ========================================
  // Upgradeability Test: Mento Labs Treasury
  // ========================================
  function test_createGovernance_mentoLabsTreasuryShouldBeUpgradeable() public i_setUp {
    vm.prank(owner);
    _createGovernance();

    ProxyAdmin proxyAdmin = factory.proxyAdmin();
    ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(factory.mentoLabsTreasuryTimelock()));

    assertEq(
      proxyAdmin.getProxyAdmin(proxy),
      address(factory.proxyAdmin()),
      "Factory: mentoLabsTreasuryProxy should have a proxyAdmin"
    );

    // we can cheat and calculate the address of the implementation contract via addressForNonce()
    address precalculatedAddress = factory.exposed_addressForNonce(7);
    address initialImpl = proxyAdmin.getProxyImplementation(proxy);
    assertEq(initialImpl, precalculatedAddress, "Factory: mentoLabsTreasuryProxy should have an implementation");

    // deploy and upgrade to new implementation
    TimelockController newImplContract = new TimelockController();
    vm.prank(address(factory.governanceTimelock()));
    proxyAdmin.upgrade(proxy, address(newImplContract));

    address newImpl = proxyAdmin.getProxyImplementation(proxy);
    assertFalse(initialImpl == newImpl, "Factory: mentoLabsTreasuryProxy should have a new implementation");
    assertTrue(
      newImpl == address(newImplContract),
      "Factory: mentoLabsTreasuryProxy implementation should equal newImpl"
    );
  }

  // ========================================
  // Upgradeability Test: Immutable Contracts
  // ========================================
  function test_createGovernance_otherContractsShouldBeImmutable() public i_setUp {
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
  }

  // ==================================
  // GovernanceFactory.addressForNonce
  // ==================================
  function testFuzz_addressForNonce_whenNoncesAreIdentical_shouldReturnTheSameAddress(uint256 nonce) public i_setUp {
    address account0 = factory.exposed_addressForNonce(nonce);
    address account1 = factory.exposed_addressForNonce(nonce);
    assertTrue(account0 == account1, "addressForNonce: Should return same address for same nonce");
  }

  function testFuzz_addressForNonce_whenNoncesAreDifferent_shouldReturnDifferentAddresses(
    uint256 nonce1,
    uint256 nonce2
  ) public i_setUp {
    // We can only safely get 256 unique addresses because we're using
    // a uint8 nonce in the function `bytes1(uint8(nonce))`
    nonce1 = bound(nonce1, 0, 255);
    nonce2 = bound(nonce2, 0, 255);
    vm.assume(nonce1 != nonce2);
    address account1 = factory.exposed_addressForNonce(nonce1);
    address account2 = factory.exposed_addressForNonce(nonce2);
    assertFalse(account1 == account2, "addressForNonce: Should return different addresses for different nonces");
  }
}
