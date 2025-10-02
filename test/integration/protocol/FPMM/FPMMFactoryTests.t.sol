// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { FPMMBaseIntegration } from "./FPMMBaseIntegration.t.sol";

// Interfaces
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";

// OpenZeppelin
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/**
 * @title FPMMFactoryTests
 * @notice Integration tests for FPMMFactory functionality
 * @dev Tests cover deployment, management, and edge cases
 */
contract FPMMFactoryTests is FPMMBaseIntegration {
  // ============ STATE VARIABLES ============

  // ============ SETUP ============

  function setUp() public override {
    super.setUp();
  }

  // ============ FACTORY SETUP TESTS ============

  function test_initialize_whenCalledByOwner_shouldSetCorrectValues() public view {
    // Verify factory configuration
    assertEq(factory.oracleAdapter(), oracleAdapter);
    assertEq(factory.proxyAdmin(), proxyAdmin);
    assertEq(factory.governance(), governance);
    assertEq(factory.owner(), governance);

    // Verify implementation registration
    assertEq(factory.isRegisteredImplementation(address(fpmmImplementation)), true);
    address[] memory registeredImplementations = factory.registeredImplementations();
    assertEq(registeredImplementations.length, 1);
    assertEq(registeredImplementations[0], address(fpmmImplementation));
  }

  function test_initialize_whenCalledTwice_shouldRevert() public {
    vm.expectRevert("Initializable: contract is already initialized");
    factory.initialize(oracleAdapter, proxyAdmin, governance, address(fpmmImplementation));
  }

  // ============ IMPLEMENTATION MANAGEMENT TESTS ============

  function test_registerFPMMImplementation_whenCalledByOwner_shouldRegisterImplementation() public {
    address newImplementation = address(0x1234567890123456789012345678901234567890);

    vm.prank(governance);
    factory.registerFPMMImplementation(newImplementation);

    assertEq(factory.isRegisteredImplementation(newImplementation), true);
    address[] memory registeredImplementations = factory.registeredImplementations();
    assertEq(registeredImplementations.length, 2);
    assertEq(registeredImplementations[1], newImplementation);
  }

  function test_registerFPMMImplementation_whenCalledByNonOwner_shouldRevert() public {
    address newImplementation = address(0x1234567890123456789012345678901234567890);

    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    factory.registerFPMMImplementation(newImplementation);
  }

  function test_registerFPMMImplementation_whenZeroAddress_shouldRevert() public {
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.registerFPMMImplementation(address(0));
  }

  function test_registerFPMMImplementation_whenAlreadyRegistered_shouldRevert() public {
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_ALREADY_REGISTERED");
    factory.registerFPMMImplementation(address(fpmmImplementation));
  }

  function test_unregisterFPMMImplementation_whenCalledByOwner_shouldUnregisterImplementation() public {
    // Register a second implementation first
    address newImplementation = address(0x1234567890123456789012345678901234567890);
    vm.prank(governance);
    factory.registerFPMMImplementation(newImplementation);

    // Unregister the new implementation
    vm.prank(governance);
    factory.unregisterFPMMImplementation(newImplementation, 1);

    assertEq(factory.isRegisteredImplementation(newImplementation), false);
    address[] memory registeredImplementations = factory.registeredImplementations();
    assertEq(registeredImplementations.length, 1);
  }

  function test_unregisterFPMMImplementation_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    factory.unregisterFPMMImplementation(address(fpmmImplementation), 0);
  }

  function test_unregisterFPMMImplementation_whenNotRegistered_shouldRevert() public {
    address nonRegisteredImplementation = address(0x1234567890123456789012345678901234567890);

    vm.prank(governance);
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");
    factory.unregisterFPMMImplementation(nonRegisteredImplementation, 0);
  }

  function test_unregisterFPMMImplementation_whenInvalidIndex_shouldRevert() public {
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: INDEX_OUT_OF_BOUNDS");
    factory.unregisterFPMMImplementation(address(fpmmImplementation), 1);
  }

  function test_unregisterFPMMImplementation_whenIndexMismatch_shouldRevert() public {
    // Register a second implementation
    address newImplementation = address(0x1234567890123456789012345678901234567890);
    vm.prank(governance);
    factory.registerFPMMImplementation(newImplementation);

    // Try to unregister with wrong index
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_INDEX_MISMATCH");
    factory.unregisterFPMMImplementation(newImplementation, 0);
  }

  // ============ POOL DEPLOYMENT TESTS ============

  function test_deployFPMM_whenCalledByOwner_shouldDeployPool() public {
    vm.prank(governance);

    address fpmm = factory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenB),
      referenceRateFeedID,
      false
    );

    assertTrue(fpmm != address(0));

    // Verify token ordering and symbol
    if (address(tokenA) < address(tokenB)) {
      assertEq(IFPMM(fpmm).token0(), address(tokenA));
      assertEq(IFPMM(fpmm).token1(), address(tokenB));
      assertEq(IERC20(fpmm).symbol(), "FPMM-TKA/TKB");
    } else {
      assertEq(IFPMM(fpmm).token0(), address(tokenB));
      assertEq(IFPMM(fpmm).token1(), address(tokenA));
      assertEq(IERC20(fpmm).symbol(), "FPMM-TKB/TKA");
    }

    (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

    assertEq(factory.getPool(token0, token1), fpmm);
    assertEq(factory.getPool(token1, token0), fpmm);
    assertTrue(factory.isPool(fpmm));

    // Verify FPMM configuration
    assertEq(address(IFPMM(fpmm).oracleAdapter()), oracleAdapter);
    assertEq(IFPMM(fpmm).referenceRateFeedID(), referenceRateFeedID);
    assertEq(OwnableUpgradeable(fpmm).owner(), governance);
  }

  function test_deployFPMM_whenCalledByNonOwner_shouldRevert() public {
    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    factory.deployFPMM(address(fpmmImplementation), address(tokenA), address(tokenB), referenceRateFeedID, false);
  }

  function test_deployFPMM_whenImplementationNotRegistered_shouldRevert() public {
    address nonRegisteredImplementation = address(0x1234567890123456789012345678901234567890);

    vm.prank(governance);
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");
    factory.deployFPMM(nonRegisteredImplementation, address(tokenA), address(tokenB), referenceRateFeedID, false);
  }

  function test_deployFPMM_whenPoolAlreadyExists_shouldRevert() public {
    // Deploy first pool
    vm.prank(governance);
    factory.deployFPMM(address(fpmmImplementation), address(tokenA), address(tokenB), referenceRateFeedID, false);

    // Try to deploy again
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: PAIR_ALREADY_EXISTS");
    factory.deployFPMM(address(fpmmImplementation), address(tokenA), address(tokenB), referenceRateFeedID, false);
  }

  function test_deployFPMM_whenZeroReferenceRateFeedID_shouldRevert() public {
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.deployFPMM(address(fpmmImplementation), address(tokenA), address(tokenB), address(0), false);
  }

  function test_deployFPMM_whenCustomParameters_shouldDeployWithCustomConfig() public {
    address customOracleAdapter = makeAddr("customOracleAdapter");
    address customProxyAdmin = makeAddr("customProxyAdmin");
    address customGovernance = makeAddr("customGovernance");

    vm.prank(governance);
    address fpmm = factory.deployFPMM(
      address(fpmmImplementation),
      customOracleAdapter,
      customProxyAdmin,
      customGovernance,
      address(tokenA),
      address(tokenC),
      referenceRateFeedID,
      false
    );

    assertTrue(fpmm != address(0));
    assertEq(factory.getPool(address(tokenA), address(tokenC)), fpmm);
    assertTrue(factory.isPool(fpmm));

    // Verify custom configuration
    assertEq(address(IFPMM(fpmm).oracleAdapter()), customOracleAdapter);
    assertEq(OwnableUpgradeable(fpmm).owner(), customGovernance);

    bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    address admin = address(uint160(uint256(vm.load(fpmm, adminSlot))));
    assertEq(admin, customProxyAdmin);
  }

  // ============ POOL QUERY TESTS ============

  function test_isPool_whenPoolExists_shouldReturnTrue() public {
    vm.prank(governance);
    address fpmm = factory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenB),
      referenceRateFeedID,
      false
    );

    assertTrue(factory.isPool(fpmm));
  }

  function test_getPool_whenPoolDoesNotExist_shouldReturnZeroAddress() public view {
    assert(factory.getPool(address(tokenA), address(tokenB)) == address(0));
    assert(factory.getPool(address(tokenB), address(tokenA)) == address(0));
  }

  function test_getPool_whenPoolExists_shouldReturnPoolAddress() public {
    vm.prank(governance);
    address fpmm = factory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenB),
      referenceRateFeedID,
      false
    );

    (address token0, address token1) = _sortTokens(address(tokenA), address(tokenB));

    assertEq(factory.getPool(token0, token1), fpmm);
    assertEq(factory.getPool(token1, token0), fpmm);
  }

  function test_deployedFPMMAddresses_whenPoolsDeployed_shouldReturnAllAddresses() public {
    vm.prank(governance);
    address fpmm1 = factory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenB),
      referenceRateFeedID,
      false
    );

    vm.prank(governance);
    address fpmm2 = factory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenC),
      referenceRateFeedID,
      false
    );

    address[] memory deployedAddresses = factory.deployedFPMMAddresses();
    assertEq(deployedAddresses.length, 2);
    assertEq(deployedAddresses[0], fpmm1);
    assertEq(deployedAddresses[1], fpmm2);
  }

  // ============ ADDRESS COMPUTATION TESTS ============

  function test_getOrPrecomputeProxyAddress_whenPoolExists_shouldReturnActualAddress() public {
    vm.prank(governance);
    address fpmm = factory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenB),
      referenceRateFeedID,
      false
    );

    address computedAddress = factory.getOrPrecomputeProxyAddress(address(tokenA), address(tokenB));
    address computedAddress2 = factory.getOrPrecomputeProxyAddress(address(tokenB), address(tokenA));
    assertEq(computedAddress, fpmm);
    assertEq(computedAddress2, fpmm);
  }

  function test_getOrPrecomputeProxyAddress_whenPoolDoesNotExist_shouldReturnPrecomputedAddress() public {
    address precomputedAddress = factory.getOrPrecomputeProxyAddress(address(tokenA), address(tokenB));
    assertTrue(precomputedAddress != address(0));
    assertEq(factory.getPool(address(tokenA), address(tokenB)), address(0));

    vm.prank(governance);
    address fpmm = factory.deployFPMM(
      address(fpmmImplementation),
      address(tokenA),
      address(tokenB),
      referenceRateFeedID,
      false
    );
    assertEq(precomputedAddress, fpmm);
  }

  function test_getOrPrecomputeProxyAddress_whenTokensReversed_shouldReturnSameAddress() public view {
    address address1 = factory.getOrPrecomputeProxyAddress(address(tokenA), address(tokenB));
    address address2 = factory.getOrPrecomputeProxyAddress(address(tokenB), address(tokenA));
    assertEq(address1, address2);
  }

  // ============ TOKEN SORTING TESTS ============

  function test_sortTokens_whenTokenALessThanTokenB_shouldReturnCorrectOrder() public view {
    address token0 = address(0x0000000000000000000000000000000000000011);
    address token1 = address(0x0000000000000000000000000000000000000022);

    (address sorted0, address sorted1) = factory.sortTokens(token0, token1);
    assertEq(sorted0, token0);
    assertEq(sorted1, token1);
  }

  function test_sortTokens_whenTokenAGreaterThanTokenB_shouldReturnCorrectOrder() public view {
    address token0 = address(0x0000000000000000000000000000000000000011);
    address token1 = address(0x0000000000000000000000000000000000000022);

    (address sorted0, address sorted1) = factory.sortTokens(token1, token0);
    assertEq(sorted0, token0);
    assertEq(sorted1, token1);
  }

  function test_sortTokens_whenSameTokens_shouldRevert() public {
    vm.expectRevert("FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");
    factory.sortTokens(address(tokenA), address(tokenA));
  }

  function test_sortTokens_whenZeroAddress_shouldRevert() public {
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.sortTokens(address(0), address(tokenA));
  }

  // ============ ADMIN FUNCTION TESTS ============

  function test_setOracleAdapter_whenCalledByOwner_shouldUpdateAddress() public {
    address newOracleAdapter = makeAddr("newOracleAdapter");

    vm.prank(governance);
    factory.setOracleAdapter(newOracleAdapter);

    assertEq(factory.oracleAdapter(), newOracleAdapter);
  }

  function test_setOracleAdapter_whenCalledByNonOwner_shouldRevert() public {
    address newOracleAdapter = makeAddr("newOracleAdapter");

    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    factory.setOracleAdapter(newOracleAdapter);
  }

  function test_setOracleAdapter_whenZeroAddress_shouldRevert() public {
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.setOracleAdapter(address(0));
  }

  function test_setProxyAdmin_whenCalledByOwner_shouldUpdateAddress() public {
    address newProxyAdmin = makeAddr("newProxyAdmin");

    vm.prank(governance);
    factory.setProxyAdmin(newProxyAdmin);

    assertEq(factory.proxyAdmin(), newProxyAdmin);
  }

  function test_setProxyAdmin_whenCalledByNonOwner_shouldRevert() public {
    address newProxyAdmin = makeAddr("newProxyAdmin");

    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    factory.setProxyAdmin(newProxyAdmin);
  }

  function test_setProxyAdmin_whenZeroAddress_shouldRevert() public {
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.setProxyAdmin(address(0));
  }

  function test_setGovernance_whenCalledByOwner_shouldUpdateAddress() public {
    address newGovernance = makeAddr("newGovernance");

    vm.prank(governance);
    factory.setGovernance(newGovernance);

    assertEq(factory.governance(), newGovernance);
    assertEq(factory.owner(), newGovernance);
  }

  function test_setGovernance_whenCalledByNonOwner_shouldRevert() public {
    address newGovernance = makeAddr("newGovernance");

    vm.prank(alice);
    vm.expectRevert("Ownable: caller is not the owner");
    factory.setGovernance(newGovernance);
  }

  function test_setGovernance_whenZeroAddress_shouldRevert() public {
    vm.prank(governance);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.setGovernance(address(0));
  }
}
