pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { TestSetup } from "./TestSetup.sol";
import { Factory } from "contracts/governance/Factory.sol";

contract FactoryTest is TestSetup {
  Factory public factory;

  address public communityMultisig = makeAddr("CommunityMultisig");
  address public vestingContract = makeAddr("VestingContract");
  address public treasuryContract = makeAddr("TreasuryContract");
  address public emissionContract = makeAddr("EmissionContract");
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809; // Mock root
  uint256 public fractalSignerPk = 0x482884244ee9b1395a512003ca42e05c2af40cd8d3eeeb375db4759a17c58437; // Mock PK;
  uint256 public fractalMaxAge = 15724800; // ~6 months
  uint32 public cliffPeriod = 14;
  uint32 public slopePeriod = 14;

  function setUp() public {
    skip(30 days);
  }

  function _newFactory() internal {
    factory = new Factory(owner);
  }

  /// @notice Create and initialize an Airgrab.
  function _createGovernance() internal {
    factory.createGovernance(vestingContract, treasuryContract, communityMultisig, merkleRoot, fractalSigner);
  }

  // ========================================
  // Factory.constructor
  // ========================================
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /// @notice Subject of the section: Factory constructor
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
  // Factory.createGovernance
  // ========================================
  /// @notice Subject of the section: Factory createGovernance
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

  /// @dev tests if the contracts are created
  function test_createGovernance_whenCallerOwner_shoulCreateAndSetContracts() public i_setUp {
    vm.prank(owner);
    cg_subject();

    assertEq(factory.mentoToken().symbol(), "MENTO");
    assertEq(factory.emission().TOTAL_EMISSION_SUPPLY(), 650_000_000 * 10**18);
    assertEq(factory.airgrab().root(), merkleRoot);
    assertEq(factory.timelockController().getMinDelay(), 7 days);
    assertEq(factory.mentoGovernor().votingPeriod(), BLOCKS_WEEK);
    assertEq(factory.locking().symbol(), "veMENTO");

    assertEq(factory.vesting(), vestingContract);
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
}
