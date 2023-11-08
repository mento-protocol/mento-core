pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { TestSetup } from "./TestSetup.sol";
import { GovernanceFactory } from "contracts/governance/GovernanceFactory.sol";

contract GovernanceFactoryTest is TestSetup {
  GovernanceFactory public factory;

  address public communityMultisig = makeAddr("CommunityMultisig");
  address public mentolabsVestingMultisig = makeAddr("MentoLabsVestingMultisig");
  address public treasuryContract = makeAddr("TreasuryContract");
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809; // Mock root

  function setUp() public {
    skip(30 days);
    vm.roll(30 * BLOCKS_DAY);
  }

  function _newFactory() internal {
    factory = new GovernanceFactory(owner, address(0), address(0));
  }

  function _createGovernance() internal {
    factory.createGovernance(
      mentolabsVestingMultisig,
      communityMultisig,
      merkleRoot,
      fractalSigner
    );
  }

  // ========================================
  // GovernanceFactory.constructor
  // ========================================
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /// @notice Subject of the section: GovernanceFactory constructor
  function c_subject() internal {
    _newFactory();
  }

  function test_constructor_setsOwner() public {
    vm.prank(alice);
    vm.expectEmit(true, true, true, true);
    emit OwnershipTransferred(alice, owner);
    c_subject();

    assertEq(address(factory.owner()), owner);
  }

  // ========================================
  // GovernanceFactory.createGovernance
  // ========================================
  /// @notice Subject of the section: GovernanceFactory createGovernance
  /// @notice setup for initialize tests
  modifier i_setUp() {
    _newFactory();
    _;
  }

  function cg_subject() internal {
    _createGovernance();
  }

  function test_createGovernance_whenCallerNotOwner_shouldRevert() public i_setUp {
    vm.expectRevert("Ownable: caller is not the owner");
    cg_subject();
  }

  function test_createGovernance_whenCallerOwner_shoulCreateAndSetContracts() public i_setUp {
    vm.prank(owner);
    cg_subject();

    assertEq(factory.mentoToken().symbol(), "MENTO");
    assertEq(factory.emission().TOTAL_EMISSION_SUPPLY(), 650_000_000 * 10**18);
    assertEq(factory.airgrab().root(), merkleRoot);
    assertEq(factory.timelockController().getMinDelay(), 2 days);
    assertEq(factory.mentoGovernor().votingPeriod(), BLOCKS_WEEK);
    assertEq(factory.locking().symbol(), "veMENTO");

    assertEq(factory.mentolabsVestingMultisig(), mentolabsVestingMultisig);
    assertEq(factory.treasury(), treasuryContract);
    assertEq(factory.initialized(), true);
  }

  function test_createGovernance_whenCalledTwice_shouldRevert() public i_setUp {
    vm.prank(owner);
    cg_subject();

    vm.prank(owner);
    vm.expectRevert("Factory: governance already created");
    cg_subject();
  }

  function test_createGovernance_shouldSetOwners() public i_setUp {
    vm.prank(owner);
    cg_subject();
    address timelock = address(factory.timelockController());
    assertEq(factory.emission().owner(), timelock);
    assertEq(factory.locking().owner(), timelock);
  }
}
