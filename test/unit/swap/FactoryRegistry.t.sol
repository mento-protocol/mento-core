// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Test } from "forge-std/Test.sol";
import { FactoryRegistry } from "contracts/swap/FactoryRegistry.sol";
import { IFactoryRegistry } from "contracts/interfaces/IFactoryRegistry.sol";

contract FactoryRegistryTest is Test {
  /* ------- Events from FactoryRegistry ------- */
  event Approve(address indexed poolFactory);
  event Unapprove(address indexed poolFactory);
  /* ------- Events from Initializable --------- */
  event Initialized(uint8 version);
  /* ------- Events from OwnableUpgradeable ---- */
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  /* ------------------------------------------- */

  address internal deployer = makeAddr("deployer");
  address internal governance = makeAddr("governance");
  address internal fallbackFactory = makeAddr("fallbackFactory");
  address internal poolFactory1 = makeAddr("poolFactory1");
  address internal poolFactory2 = makeAddr("poolFactory2");
  FactoryRegistry internal factoryRegistry;

  modifier afterInit() {
    factoryRegistry.initialize(fallbackFactory, governance);
    _;
  }

  function setUp() public {
    vm.prank(deployer);
    factoryRegistry = new FactoryRegistry(false);
  }

  function test_constructor_whenDisableTrue_shouldDisableInitializers() public {
    FactoryRegistry initializableFactoryRegistry = new FactoryRegistry(true);
    vm.expectRevert("Initializable: contract is already initialized");
    initializableFactoryRegistry.initialize(fallbackFactory, governance);
  }

  function test_constructor_whenDisableFalse_shouldNotDisableInitializers() public {
    vm.expectEmit(false, false, false, true, address(factoryRegistry));
    emit Initialized(1);
    factoryRegistry.initialize(fallbackFactory, governance);
  }

  function test_initialize_shouldSetOwnerToGovernance() public {
    vm.prank(deployer);
    vm.expectEmit(true, true, false, false, address(factoryRegistry));
    emit OwnershipTransferred(address(0), deployer);
    vm.expectEmit(true, true, false, false, address(factoryRegistry));
    emit OwnershipTransferred(deployer, governance);
    factoryRegistry.initialize(fallbackFactory, governance);
    assertEq(factoryRegistry.owner(), governance);
  }

  function test_initialize_shouldSetFallbackFactory() public afterInit {
    assertEq(factoryRegistry.fallbackPoolFactory(), fallbackFactory);
  }

  function test_approve_whenCallerIsNotOwner_shouldRevert() public afterInit {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("notOwner"));
    factoryRegistry.approve(poolFactory1);
  }

  function test_approve_whenZeroAddress_shouldRevert() public afterInit {
    vm.expectRevert(IFactoryRegistry.ZeroAddress.selector);
    vm.prank(governance);
    factoryRegistry.approve(address(0));
  }

  function test_unapprove_whenFallbackFactory_shouldRevert() public afterInit {
    vm.expectRevert(IFactoryRegistry.FallbackFactory.selector);
    vm.prank(governance);
    factoryRegistry.unapprove(fallbackFactory);
  }

  function test_unapprove_whenUnknownFactory_shouldRevert() public afterInit {
    vm.expectRevert(IFactoryRegistry.PathNotApproved.selector);
    vm.prank(governance);
    factoryRegistry.unapprove(makeAddr("unknown"));
  }

  function test_approve_whenKnownPath_shouldRevert() public afterInit {
    vm.startPrank(governance);
    factoryRegistry.approve(makeAddr("known"));
    vm.expectRevert(IFactoryRegistry.PathAlreadyApproved.selector);
    factoryRegistry.approve(makeAddr("known"));
    vm.stopPrank();
  }

  function test_approve_whenFallbackFactory_shouldRevert() public afterInit {
    vm.startPrank(governance);
    vm.expectRevert(IFactoryRegistry.PathAlreadyApproved.selector);
    factoryRegistry.approve(fallbackFactory);
    vm.stopPrank();
  }

  function test_approve_shouldEmitEventsAndUpdateState() public afterInit {
    assert(!factoryRegistry.isPoolFactoryApproved(poolFactory1));
    assert(!factoryRegistry.isPoolFactoryApproved(poolFactory2));
    address[] memory factories = factoryRegistry.poolFactories();
    assertEq(factories.length, 1);
    assertEq(factoryRegistry.poolFactoriesLength(), 1);

    vm.startPrank(governance);
    vm.expectEmit(true, false, false, false, address(factoryRegistry));
    emit Approve(poolFactory1);
    factoryRegistry.approve(poolFactory1);
    assert(factoryRegistry.isPoolFactoryApproved(poolFactory1));
    assert(!factoryRegistry.isPoolFactoryApproved(poolFactory2));
    factories = factoryRegistry.poolFactories();
    assertEq(factories.length, 2);
    assertEq(factories[0], fallbackFactory);
    assertEq(factories[1], poolFactory1);
    assertEq(factoryRegistry.poolFactoriesLength(), 2);

    vm.expectEmit(true, false, false, false, address(factoryRegistry));
    emit Approve(poolFactory2);
    factoryRegistry.approve(poolFactory2);
    assert(factoryRegistry.isPoolFactoryApproved(poolFactory1));
    assert(factoryRegistry.isPoolFactoryApproved(poolFactory2));
    factories = factoryRegistry.poolFactories();
    assertEq(factories.length, 3);
    assertEq(factories[0], fallbackFactory);
    assertEq(factories[1], poolFactory1);
    assertEq(factories[2], poolFactory2);
    assertEq(factoryRegistry.poolFactoriesLength(), 3);
  }
}
