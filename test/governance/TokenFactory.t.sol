pragma solidity 0.8.18;
// solhint-disable func-name-mixedcase

import { TestSetup } from "./TestSetup.sol";
import { TokenFactory } from "contracts/governance/TokenFactory.sol";
import { Locking } from "contracts/governance/locking/Locking.sol";
import { TransparentUpgradeableProxy, ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "openzeppelin-contracts-next/contracts/proxy/transparent/ProxyAdmin.sol";

import { MockOwnable } from "../mocks/MockOwnable.sol";

contract TokenFactoryTest is TestSetup {
  TokenFactory public factory;
  address public lockingImplementation;
  MockOwnable public mockImplementation;

  address public vestingContract = makeAddr("VestingContract");
  address public mentoMultisig = makeAddr("MentoMultisig");
  address public treasuryContract = makeAddr("TreasuryContract");
  address public fractalSigner = makeAddr("FractalSigner");

  bytes32 public merkleRoot = 0x945d83ced94efc822fed712b4c4694b4e1129607ec5bbd2ab971bb08dca4d809; // Mock root

  function setUp() public {
    skip(30 days);
    vm.roll(30 * BLOCKS_DAY);
    lockingImplementation = address(new Locking());
    mockImplementation = new MockOwnable();
  }

  function _newFactory() internal {
    factory = new TokenFactory(owner);
  }

  /// @notice Create and initialize an Airgrab.
  function _createTokenContracts() internal {
    factory.createTokenContracts(
      vestingContract,
      mentoMultisig,
      treasuryContract,
      merkleRoot,
      fractalSigner,
      lockingImplementation
    );
  }

  // ========================================
  // TokenFactory.constructor
  // ========================================
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /// @notice Subject of the section: TokenFactory constructor
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
  // TokenFactory.createTokenContracts
  // ========================================
  /// @notice Subject of the section: TokenFactory createTokenContracts
  /// @notice setup for initialize tests
  modifier i_setUp() {
    _newFactory();
    _;
  }

  function cg_subject() internal {
    _createTokenContracts();
  }

  function test_createTokenContracts_whenCallerNotOwner_shouldRevert() public i_setUp {
    vm.expectRevert("Ownable: caller is not the owner");
    cg_subject();
  }

  function test_createTokenContracts_whenCallerOwner_shoulCreateAndSetContracts() public i_setUp {
    vm.prank(owner);
    cg_subject();

    assertEq(factory.mentoToken().symbol(), "MENTO");
    assertEq(factory.emission().TOTAL_EMISSION_SUPPLY(), 650_000_000 * 10**18);
    assertEq(factory.airgrab().root(), merkleRoot);
    assertEq(factory.locking().symbol(), "veMENTO");

    assertEq(factory.vesting(), vestingContract);
    assertEq(factory.mentoMultisig(), mentoMultisig);
    assertEq(factory.treasury(), treasuryContract);
    assertEq(factory.initialized(), true);
  }

  function test_createTokenContracts_whenCalledTwice_shouldRevert() public i_setUp {
    vm.prank(owner);
    cg_subject();

    vm.prank(owner);
    vm.expectRevert("TokenFactory: token already created");
    cg_subject();
  }

  function test_createTokenContracts_shouldSetOwners() public i_setUp {
    vm.prank(owner);
    cg_subject();
    assertEq(factory.emission().owner(), owner);
    assertEq(factory.locking().owner(), owner);
    assertEq(factory.airgrab().owner(), address(0));
  }
}
