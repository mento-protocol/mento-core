// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Test } from "forge-std/Test.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { FPMMProxy } from "contracts/swap/FPMMProxy.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { ICreateX } from "contracts/interfaces/ICreateX.sol";
// solhint-disable-next-line max-line-length
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FPMMFactoryTest is Test {
  /* ------- Events from FPMMFactory ------- */
  event FPMMDeployed(address indexed token0, address indexed token1, address fpmmProxy, address fpmmImplementation);
  event FPMMImplementationRegistered(address indexed fpmmImplementation);
  event FPMMImplementationUnregistered(address indexed fpmmImplementation);
  event ProxyAdminSet(address indexed proxyAdmin);
  event SortedOraclesSet(address indexed sortedOracles);
  event BreakerBoxSet(address indexed breakerBox);
  event GovernanceSet(address indexed governance);
  /* --------------------------------------- */

  address public deployer;
  address public createX;
  address public referenceRateFeedID;

  // Celo
  uint256 public celoFork;
  address public token0Celo;
  address public token1Celo;
  address public sortedOraclesCelo;
  address public breakerBoxCelo;
  address public proxyAdminCelo;
  address public governanceCelo;
  FPMMFactory public factoryCelo;
  FPMM public fpmmImplementationCelo;
  address public fpmmImplementationCeloAddress;

  // Optimism
  uint256 public opFork;
  address public token0Op;
  address public token1Op;
  address public sortedOraclesOp;
  address public breakerBoxOp;
  address public proxyAdminOp;
  address public governanceOp;
  FPMMFactory public factoryOp;
  FPMM public fpmmImplementationOp;
  address public fpmmImplementationOpAddress;

  function setUp() public virtual {
    createX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    deployer = makeAddr("Deployer");
    referenceRateFeedID = makeAddr("token0/token1");

    celoFork = vm.createFork("https://forno.celo.org");
    token0Celo = 0x0000000000000000000000000000000000000c31;
    token1Celo = 0x0000000000000000000000000000000000000c32;
    sortedOraclesCelo = makeAddr("SortedOracles Celo");
    breakerBoxCelo = makeAddr("BreakerBox Celo");
    proxyAdminCelo = makeAddr("ProxyAdmin Celo");
    governanceCelo = makeAddr("Governance Celo");
    fpmmImplementationCelo = new FPMM(true);
    fpmmImplementationCeloAddress = address(fpmmImplementationCelo);
    vm.makePersistent(address(fpmmImplementationCelo));

    opFork = vm.createFork("https://mainnet.optimism.io");
    token0Op = 0x0000000000000000000000000000000000000c39;
    token1Op = 0x0000000000000000000000000000000000000C3a;
    sortedOraclesOp = makeAddr("SortedOracles Optimism");
    breakerBoxOp = makeAddr("BreakerBox Optimism");
    proxyAdminOp = makeAddr("ProxyAdmin Optimism");
    governanceOp = makeAddr("Governance Optimism");
    fpmmImplementationOp = new FPMM(true);
    fpmmImplementationOpAddress = address(fpmmImplementationOp);
    vm.makePersistent(address(fpmmImplementationOp));
  }
}

contract FPMMFactoryTest_InitializerSettersGetters is FPMMFactoryTest {
  function setUp() public override {
    super.setUp();
  }

  function test_constructor_whenDisableTrue_shouldDisableInitializers() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(true);
    vm.expectRevert("Initializable: contract is already initialized");
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
  }
  function test_constructor_whenDisableFalse_shouldNotDisableInitializers() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
  }

  function test_constructor_whenCreateXNotDeployed_shouldRevert() public {
    vm.expectRevert("FPMMFactory: CREATEX_BYTECODE_HASH_MISMATCH");
    factoryCelo = new FPMMFactory(false);
  }

  function test_constructor_whenDifferentContractIsDeployedToCreateXAddress_shouldNotRevert() public {
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), createX);
    vm.expectRevert("FPMMFactory: CREATEX_BYTECODE_HASH_MISMATCH");
    factoryCelo = new FPMMFactory(false);
  }

  function test_initialize_shouldSetOwner() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.prank(deployer);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    assertEq(factoryCelo.owner(), governanceCelo);
  }

  function test_initialize_whenSortedOraclesIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(address(0), proxyAdminCelo, breakerBoxCelo, governanceCelo, address(fpmmImplementationCelo));
  }

  function test_initialize_whenProxyAdminIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(
      sortedOraclesCelo,
      address(0),
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
  }

  function test_initialize_whenBreakerBoxIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      address(0),
      governanceCelo,
      address(fpmmImplementationCelo)
    );
  }

  function test_initialize_whenFPMMImplementationIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo, address(0));
  }

  function test_initialize_whenGovernanceIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      address(0),
      address(fpmmImplementationCelo)
    );
  }

  function test_initialized_shouldSetVariablesAndEmitEvents() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);

    vm.expectEmit();
    emit ProxyAdminSet(proxyAdminCelo);
    vm.expectEmit();
    emit SortedOraclesSet(sortedOraclesCelo);
    vm.expectEmit();
    emit BreakerBoxSet(breakerBoxCelo);
    vm.expectEmit();
    emit FPMMImplementationRegistered(address(fpmmImplementationCelo));
    vm.expectEmit();
    emit GovernanceSet(governanceCelo);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    assertEq(factoryCelo.sortedOracles(), sortedOraclesCelo);
    assertEq(factoryCelo.proxyAdmin(), proxyAdminCelo);
    assertEq(factoryCelo.breakerBox(), breakerBoxCelo);
    assertEq(factoryCelo.isRegisteredImplementation(address(fpmmImplementationCelo)), true);
    address[] memory registeredImplementations = factoryCelo.registeredImplementations();
    assertEq(registeredImplementations.length, 1);
    assertEq(registeredImplementations[0], address(fpmmImplementationCelo));
    assertEq(factoryCelo.governance(), governanceCelo);
    assertEq(factoryCelo.owner(), governanceCelo);
  }

  function test_setSortedOracles_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setSortedOracles(makeAddr("New SortedOracles"));
  }

  function test_setSortedOracles_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setSortedOracles(address(0));
  }

  function test_setSortedOracles_shouldSetSortedOraclesAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    address newSortedOracles = makeAddr("New SortedOracles");
    vm.expectEmit();
    emit SortedOraclesSet(newSortedOracles);
    vm.prank(governanceCelo);
    factoryCelo.setSortedOracles(newSortedOracles);

    assertEq(factoryCelo.sortedOracles(), newSortedOracles);
  }

  function test_setProxyAdmin_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setProxyAdmin(makeAddr("New ProxyAdmin"));
  }

  function test_setProxyAdmin_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setProxyAdmin(address(0));
  }

  function test_setProxyAdmin_shouldSetProxyAdminAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    address newProxyAdmin = makeAddr("New ProxyAdmin");
    vm.expectEmit();
    emit ProxyAdminSet(newProxyAdmin);
    vm.prank(governanceCelo);
    factoryCelo.setProxyAdmin(newProxyAdmin);

    assertEq(factoryCelo.proxyAdmin(), newProxyAdmin);
  }

  function test_setBreakerBox_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setBreakerBox(makeAddr("New BreakerBox"));
  }

  function test_setBreakerBox_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setBreakerBox(address(0));
  }

  function test_setBreakerBox_shouldSetBreakerBoxAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    address newBreakerBox = makeAddr("New BreakerBox");
    vm.expectEmit();
    emit BreakerBoxSet(newBreakerBox);
    vm.prank(governanceCelo);
    factoryCelo.setBreakerBox(newBreakerBox);

    assertEq(factoryCelo.breakerBox(), newBreakerBox);
  }

  function test_setGovernance_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setGovernance(makeAddr("New Governance"));
  }

  function test_setGovernance_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setGovernance(address(0));
  }

  function test_setGovernance_shouldSetGovernanceAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    address newGovernance = makeAddr("New Governance");
    vm.expectEmit();
    emit GovernanceSet(newGovernance);
    vm.prank(governanceCelo);
    factoryCelo.setGovernance(newGovernance);

    assertEq(factoryCelo.governance(), newGovernance);
  }

  function test_registerImplementation_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.registerFPMMImplementation(address(fpmmImplementationCelo));
  }

  function test_registerImplementation_whenImplementationIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.registerFPMMImplementation(address(0));
  }

  function test_registerImplementation_whenImplementationIsAlreadyRegistered_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.startPrank(governanceCelo);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_ALREADY_REGISTERED");
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.stopPrank();
  }

  function test_registerImplementation_whenImplementationIsNotRegistered_shouldRegisterImplementationAndEmitEvent()
    public
  {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMImplementationRegistered(makeAddr("Implementation2"));
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.stopPrank();
  }

  function test_unregisterImplementation_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 0);
  }

  function test_unregisterImplementation_whenImplementationIsNotRegistered_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");
    vm.prank(governanceCelo);
    factoryCelo.unregisterFPMMImplementation(makeAddr("Implementation2"), 0);
  }

  function test_unregisterImplemenattion_whenIndexIsOutOfBounds_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.expectRevert("FPMMFactory: INDEX_OUT_OF_BOUNDS");
    vm.prank(governanceCelo);
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 1);
  }

  function test_unregisterImplementation_whenImplementationAddressAndIndexDoNotMatch_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.startPrank(governanceCelo);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_INDEX_MISMATCH");
    factoryCelo.unregisterFPMMImplementation(makeAddr("Implementation2"), 0);
    vm.stopPrank();
  }

  function test_unregisterImplementation_shouldUnregisterImplementationAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMImplementationUnregistered(address(fpmmImplementationCelo));
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 0);

    assertEq(factoryCelo.registeredImplementations().length, 0);
    assertEq(factoryCelo.isRegisteredImplementation(address(fpmmImplementationCelo)), false);
  }

  function test_unregisterImplementation_whenMultipleImplementations_shouldUnregisterImplementationAndEmitEvent()
    public
  {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
    vm.prank(governanceCelo);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMImplementationUnregistered(address(fpmmImplementationCelo));
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 0);

    assertEq(factoryCelo.registeredImplementations().length, 1);
    assertEq(factoryCelo.isRegisteredImplementation(address(fpmmImplementationCelo)), false);
    assertEq(factoryCelo.isRegisteredImplementation(makeAddr("Implementation2")), true);
    assertEq(factoryCelo.registeredImplementations()[0], makeAddr("Implementation2"));
  }

  function test_getOrPrecomputeProxyAddress_whenContractIsNotDeployed_shouldReturnCorrectPrecomputedAddress() public {
    vm.selectFork(celoFork);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Celo);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Celo);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );

    address precomputedProxy = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);

    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      token0Celo,
      token1Celo,
      referenceRateFeedID
    );

    assertEq(deployedProxy, precomputedProxy);
  }
}

abstract contract FPMMFactoryTest_DeployFPMM is FPMMFactoryTest {
  address public expectedImplementation;
  address public expectedProxy;
  address public expectedSortedOracles;
  address public expectedProxyAdmin;
  address public expectedBreakerBox;
  address public expectedGovernance;
  address public expectedToken0;
  address public expectedToken1;
  address public expectedReferenceRateFeedID;

  function deploy(string memory chain) internal virtual returns (address);

  function setUp() public virtual override {
    super.setUp();
    vm.selectFork(celoFork);
    vm.prank(deployer);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      fpmmImplementationCeloAddress
    );
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Celo);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Celo);
  }

  function test_deployFPMM_whenCallerIsNotOwner_shouldRevert() public {
    vm.prank(makeAddr("Not Owner"));
    vm.expectRevert("Ownable: caller is not the owner");
    deploy("celo");
  }

  function test_deployFPMM_whenImplementationIsNotRegistered_shouldRevert() public {
    fpmmImplementationCeloAddress = makeAddr("Not Registered Implementation");
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");
    deploy("celo");
  }

  function test_deployFPMM_whenToken0OrToken1IsZeroAddress_shouldRevert() public {
    token0Celo = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    deploy("celo");

    token0Celo = makeAddr("Token 0 Celo");
    token1Celo = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    deploy("celo");
  }

  function test_deployFPMM_whenToken0AndToken1AreSame_shouldRevert() public {
    token0Celo = token1Celo;
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");
    deploy("celo");
  }

  function test_deployFPMM_whenPairAlreadyExists_shouldRevert() public {
    vm.prank(governanceCelo);
    deploy("celo");
    vm.expectRevert("FPMMFactory: PAIR_ALREADY_EXISTS");
    vm.prank(governanceCelo);
    deploy("celo");
  }

  function test_deployFPMM_whenReferenceRateFeedIDIsZeroAddress_shouldRevert() public {
    referenceRateFeedID = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    deploy("celo");
  }

  function testdeployFPMM_shouldUpdateAndEmit() public {
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMDeployed(expectedToken0, expectedToken1, expectedProxy, expectedImplementation);
    address deployedProxy = deploy("celo");

    assertEq(deployedProxy, expectedProxy);
    assertEq(factoryCelo.deployedFPMMs(expectedToken0, expectedToken1), deployedProxy);
    assertEq(factoryCelo.deployedFPMMAddresses().length, 1);
    assertEq(factoryCelo.deployedFPMMAddresses()[0], deployedProxy);

    // if not pranked, the proxy will revert
    vm.prank(expectedProxyAdmin);
    address proxyAdmin = ITransparentUpgradeableProxy(deployedProxy).admin();
    assertEq(proxyAdmin, expectedProxyAdmin);

    // test that the proxy is initialized correctly
    address owner = FPMM(deployedProxy).owner();
    assertEq(owner, expectedGovernance);

    address token0 = FPMM(deployedProxy).token0();
    assertEq(token0, expectedToken0);

    address token1 = FPMM(deployedProxy).token1();
    assertEq(token1, expectedToken1);

    address breakerBox = address(FPMM(deployedProxy).breakerBox());
    assertEq(breakerBox, expectedBreakerBox);

    address _referenceRateFeedID = address(FPMM(deployedProxy).referenceRateFeedID());
    assertEq(_referenceRateFeedID, expectedReferenceRateFeedID);

    address sortedOracles = address(FPMM(deployedProxy).sortedOracles());
    assertEq(sortedOracles, expectedSortedOracles);
  }

  function test_deployFPMM_shouldRevertForSamePairInDifferentOrder() public {
    vm.prank(governanceCelo);
    deploy("celo");
    address[] memory deployedFPMMAddresses = factoryCelo.deployedFPMMAddresses();
    assertEq(deployedFPMMAddresses.length, 1);

    // deploy second pair with switched token0,token1
    token0Celo = expectedToken1;
    token1Celo = expectedToken0;
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: PAIR_ALREADY_EXISTS");
    deploy("celo");
  }

  function test_deployFPMM_whenSameSaltIsUsedByDifferentAddress_shouldNotDeployToSameAddress() public {
    vm.selectFork(celoFork);
    address alice = makeAddr("Alice");

    vm.startPrank(alice);

    bytes11 customProxySalt = bytes11(
      uint88(uint256(keccak256(abi.encodePacked(IERC20(token0Celo).symbol(), IERC20(token1Celo).symbol()))))
    );
    bytes32 proxySalt = bytes32(abi.encodePacked(address(factoryCelo), hex"00", customProxySalt));
    bytes memory proxyInitData = abi.encodeWithSelector(
      FPMM.initialize.selector,
      token0Celo,
      token1Celo,
      expectedSortedOracles,
      expectedReferenceRateFeedID,
      expectedBreakerBox,
      expectedGovernance
    );
    bytes memory proxyBytecode = abi.encodePacked(
      type(FPMMProxy).creationCode,
      abi.encode(fpmmImplementationCeloAddress, expectedProxyAdmin, proxyInitData)
    );

    address aliceFPMMProxy = ICreateX(createX).deployCreate3(proxySalt, proxyBytecode);
    vm.stopPrank();

    vm.prank(governanceCelo);
    deploy("celo");

    address factoryProxy = address(factoryCelo.deployedFPMMs(token0Celo, token1Celo));
    assertNotEq(factoryProxy, aliceFPMMProxy);
  }

  function test_deployFPMM_shouldDeploySameFPMMToSameAddressOnDifferentChains() public {
    vm.selectFork(celoFork);
    vm.prank(governanceCelo);
    address celoFPMMProxy = deploy("celo");
    assertEq(celoFPMMProxy, factoryCelo.deployedFPMMs(token0Celo, token1Celo));

    vm.selectFork(opFork);
    vm.prank(deployer);
    factoryOp = new FPMMFactory(false);
    factoryOp.initialize(sortedOraclesOp, proxyAdminOp, breakerBoxOp, governanceOp, fpmmImplementationOpAddress);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Op);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Op);

    assertEq(address(factoryOp), address(factoryCelo));

    vm.prank(governanceOp);
    address opFPMMProxy = deploy("op");
    assertEq(opFPMMProxy, factoryOp.deployedFPMMs(token0Op, token1Op));

    assertEq(opFPMMProxy, celoFPMMProxy);
  }
}

contract FPMMFactoryTest_DeployFPMMStandard is FPMMFactoryTest_DeployFPMM {
  function setUp() public override {
    super.setUp();
    expectedImplementation = fpmmImplementationCeloAddress;
    expectedProxy = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);
    expectedToken0 = token0Celo;
    expectedToken1 = token1Celo;
    expectedSortedOracles = sortedOraclesCelo;
    expectedProxyAdmin = proxyAdminCelo;
    expectedBreakerBox = breakerBoxCelo;
    expectedGovernance = governanceCelo;
    expectedReferenceRateFeedID = referenceRateFeedID;
  }

  function deploy(string memory chain) internal override returns (address) {
    if (keccak256(abi.encode(chain)) == keccak256(abi.encode("celo"))) {
      return factoryCelo.deployFPMM(fpmmImplementationCeloAddress, token0Celo, token1Celo, referenceRateFeedID);
    } else if (keccak256(abi.encode(chain)) == keccak256(abi.encode("op"))) {
      return factoryOp.deployFPMM(fpmmImplementationOpAddress, token0Op, token1Op, referenceRateFeedID);
    } else {
      return address(0);
    }
  }
}

contract FPMMFactoryTest_DeployFPMMCustom is FPMMFactoryTest_DeployFPMM {
  function setUp() public override {
    super.setUp();
    expectedImplementation = fpmmImplementationCeloAddress;
    expectedProxy = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);
    expectedToken0 = token0Celo;
    expectedToken1 = token1Celo;
    expectedSortedOracles = makeAddr("Custom Sorted Oracles");
    expectedProxyAdmin = makeAddr("Custom Proxy Admin");
    expectedBreakerBox = makeAddr("Custom Breaker Box");
    expectedGovernance = makeAddr("Custom Governance");
    expectedReferenceRateFeedID = referenceRateFeedID;
  }

  function deploy(string memory chain) internal override returns (address) {
    if (keccak256(abi.encode(chain)) == keccak256(abi.encode("celo"))) {
      return
        factoryCelo.deployFPMM(
          fpmmImplementationCeloAddress,
          expectedSortedOracles,
          expectedProxyAdmin,
          expectedBreakerBox,
          expectedGovernance,
          token0Celo,
          token1Celo,
          referenceRateFeedID
        );
    } else if (keccak256(abi.encode(chain)) == keccak256(abi.encode("op"))) {
      return
        factoryOp.deployFPMM(
          fpmmImplementationOpAddress,
          expectedSortedOracles,
          expectedProxyAdmin,
          expectedBreakerBox,
          expectedGovernance,
          token0Op,
          token1Op,
          referenceRateFeedID
        );
    } else {
      return address(0);
    }
  }

  function test_deployFPMM_whenCustomSortedOraclesIsZeroAddress_shouldRevert() public {
    expectedSortedOracles = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    deploy("celo");
  }

  function test_deployFPMM_whenCustomProxyAdminIsZeroAddress_shouldRevert() public {
    expectedProxyAdmin = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    deploy("celo");
  }

  function test_deployFPMM_whenCustomBreakerBoxIsZeroAddress_shouldRevert() public {
    expectedBreakerBox = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    deploy("celo");
  }

  function test_deployFPMM_whenCustomGovernanceIsZeroAddress_shouldRevert() public {
    expectedGovernance = address(0);
    vm.prank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    deploy("celo");
  }
}

contract FPMMFactoryTest_SortTokens is FPMMFactoryTest {
  function setUp() public override {
    super.setUp();
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(
      sortedOraclesCelo,
      proxyAdminCelo,
      breakerBoxCelo,
      governanceCelo,
      address(fpmmImplementationCelo)
    );
  }

  function testSortTokens_whenTokenAIsLessThanTokenB_shouldReturnTokensInOrder() public view {
    address tokenA = address(0x1000);
    address tokenB = address(0x2000);

    (address token0, address token1) = factoryCelo.sortTokens(tokenA, tokenB);

    assertEq(token0, tokenA);
    assertEq(token1, tokenB);
  }

  function testSortTokens_whenTokenBIsLessThanTokenA_shouldReturnTokensInOrder() public view {
    address tokenA = address(0x2000);
    address tokenB = address(0x1000);

    (address token0, address token1) = factoryCelo.sortTokens(tokenA, tokenB);

    assertEq(token0, tokenB);
    assertEq(token1, tokenA);
  }

  function testSortTokens_whenTokensAreEqual_shouldRevert() public {
    address tokenA = address(0x1000);
    address tokenB = address(0x1000);

    vm.expectRevert("FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");
    factoryCelo.sortTokens(tokenA, tokenB);
  }

  function testSortTokens_whenTokenAIsZeroAddress_shouldRevert() public {
    address tokenA = address(0);
    address tokenB = address(0x1000);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.sortTokens(tokenA, tokenB);
  }

  function testSortTokens_whenTokenBIsZeroAddress_shouldRevert() public {
    address tokenA = address(0x1000);
    address tokenB = address(0);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.sortTokens(tokenA, tokenB);
  }

  function testSortTokens_integrationWithDeployFPMM_shouldUseSortedTokens() public {
    // Deploy tokens with specific addresses
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Deploy with tokens in reverse order
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      higherToken, // token0 (higher address)
      lowerToken, // token1 (lower address)
      referenceRateFeedID
    );

    // Verify the FPMM was deployed with sorted tokens
    FPMM fpmm = FPMM(deployedProxy);
    assertEq(fpmm.token0(), lowerToken); // Should be sorted to lower address
    assertEq(fpmm.token1(), higherToken); // Should be sorted to higher address

    // Verify the factory mapping uses sorted tokens
    assertEq(factoryCelo.deployedFPMMs(lowerToken, higherToken), deployedProxy);
    assertEq(factoryCelo.deployedFPMMs(higherToken, lowerToken), address(0)); // Should not exist
  }

  function testSortTokens_integrationWithGetOrPrecomputeProxyAddress_shouldUseSortedTokens() public {
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Get precomputed address with tokens in reverse order
    address precomputedAddress = factoryCelo.getOrPrecomputeProxyAddress(higherToken, lowerToken);

    // Deploy with tokens in correct order
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      lowerToken,
      higherToken,
      referenceRateFeedID
    );

    // Verify both addresses match
    assertEq(deployedProxy, precomputedAddress);

    // Verify the factory mapping uses sorted tokens
    assertEq(factoryCelo.deployedFPMMs(lowerToken, higherToken), deployedProxy);
  }

  function testSortTokens_deploymentMappingConsistency_shouldUseSortedTokensInMapping() public {
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Deploy with tokens in reverse order
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      higherToken, // token0 (higher address)
      lowerToken, // token1 (lower address)
      referenceRateFeedID
    );

    // Verify the factory mapping only exists for sorted tokens
    assertEq(factoryCelo.deployedFPMMs(lowerToken, higherToken), deployedProxy);
    assertEq(factoryCelo.deployedFPMMs(higherToken, lowerToken), address(0));

    // Verify deployedFPMMAddresses contains the deployed proxy
    address[] memory deployedAddresses = factoryCelo.deployedFPMMAddresses();
    assertEq(deployedAddresses.length, 1);
    assertEq(deployedAddresses[0], deployedProxy);
  }

  function testSortTokens_multipleDeploymentsWithDifferentOrders_shouldMaintainConsistency() public {
    address tokenA = address(0x1000);
    address tokenB = address(0x2000);
    address tokenC = address(0x3000);

    deployCodeTo("ERC20", abi.encode("Token A", "TKA"), tokenA);
    deployCodeTo("ERC20", abi.encode("Token B", "TKB"), tokenB);
    deployCodeTo("ERC20", abi.encode("Token C", "TKC"), tokenC);

    // Deploy pair A-B with A first
    vm.prank(governanceCelo);
    address proxyAB1 = factoryCelo.deployFPMM(address(fpmmImplementationCelo), tokenA, tokenB, referenceRateFeedID);

    // Deploy pair B-C with B first
    vm.prank(governanceCelo);
    address proxyBC1 = factoryCelo.deployFPMM(address(fpmmImplementationCelo), tokenB, tokenC, referenceRateFeedID);

    // Verify mappings use sorted tokens
    assertEq(factoryCelo.deployedFPMMs(tokenA, tokenB), proxyAB1);
    assertEq(factoryCelo.deployedFPMMs(tokenB, tokenC), proxyBC1);

    // Verify reverse mappings don't exist
    assertEq(factoryCelo.deployedFPMMs(tokenB, tokenA), address(0));
    assertEq(factoryCelo.deployedFPMMs(tokenC, tokenB), address(0));

    // Verify deployed addresses list
    address[] memory deployedAddresses = factoryCelo.deployedFPMMAddresses();
    assertEq(deployedAddresses.length, 2);
    assertEq(deployedAddresses[0], proxyAB1);
    assertEq(deployedAddresses[1], proxyBC1);
  }

  function testSortTokens_getOrPrecomputeProxyAddress_shouldReturnSameAddressForDifferentOrders() public {
    address lowerToken = address(0x1000);
    address higherToken = address(0x2000);

    deployCodeTo("ERC20", abi.encode("Lower Token", "LOW"), lowerToken);
    deployCodeTo("ERC20", abi.encode("Higher Token", "HIGH"), higherToken);

    // Get precomputed addresses with different token orders
    address precomputedAddress1 = factoryCelo.getOrPrecomputeProxyAddress(lowerToken, higherToken);
    address precomputedAddress2 = factoryCelo.getOrPrecomputeProxyAddress(higherToken, lowerToken);

    // Both should return the same address
    assertEq(precomputedAddress1, precomputedAddress2);

    // Deploy the actual contract
    vm.prank(governanceCelo);
    address deployedProxy = factoryCelo.deployFPMM(
      address(fpmmImplementationCelo),
      higherToken, // Deploy with reverse order
      lowerToken,
      referenceRateFeedID
    );

    // Verify the deployed address matches both precomputed addresses
    assertEq(deployedProxy, precomputedAddress1);
    assertEq(deployedProxy, precomputedAddress2);
  }
}
