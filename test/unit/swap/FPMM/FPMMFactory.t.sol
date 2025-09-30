// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import { Test } from "forge-std/Test.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
// solhint-disable-next-line max-line-length
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts-next/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FPMMFactoryTest is Test {
  /* ------- Events from FPMMFactory ------- */
  event FPMMDeployed(address indexed token0, address indexed token1, address fpmmProxy, address fpmmImplementation);
  event FPMMImplementationRegistered(address indexed fpmmImplementation);
  event FPMMImplementationUnregistered(address indexed fpmmImplementation);
  event ProxyAdminSet(address indexed proxyAdmin);
  event OracleAdapterSet(address indexed oracleAdapter);
  event GovernanceSet(address indexed governance);
  /* --------------------------------------- */

  address public deployer;
  address public createX;
  address public referenceRateFeedID;

  // Celo
  uint256 public celoFork;
  address public token0Celo;
  address public token1Celo;
  address public oracleAdapterCelo;
  address public proxyAdminCelo;
  address public governanceCelo;
  FPMMFactory public factoryCelo;
  FPMM public fpmmImplementationCelo;
  address public fpmmImplementationCeloAddress;

  // Optimism
  uint256 public opFork;
  address public token0Op;
  address public token1Op;
  address public oracleAdapterOp;
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
    oracleAdapterCelo = makeAddr("OracleAdapter Celo");
    proxyAdminCelo = makeAddr("ProxyAdmin Celo");
    governanceCelo = makeAddr("Governance Celo");
    fpmmImplementationCelo = new FPMM(true);
    fpmmImplementationCeloAddress = address(fpmmImplementationCelo);
    vm.makePersistent(address(fpmmImplementationCelo));

    opFork = vm.createFork("https://mainnet.optimism.io");
    token0Op = 0x0000000000000000000000000000000000000c39;
    token1Op = 0x0000000000000000000000000000000000000C3a;
    oracleAdapterOp = makeAddr("OracleAdapter Optimism");
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
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
  }
  function test_constructor_whenDisableFalse_shouldNotDisableInitializers() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
  }

  function test_constructor_whenCreateXNotDeployed_shouldRevert() public {
    vm.expectRevert("FPMMFactory: CREATEX_BYTECODE_HASH_MISMATCH");
    factoryCelo = new FPMMFactory(false);
  }

  function test_constructor_whenDifferentContractIsDeployedToCreateXAddress_shouldRevert() public {
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), createX);
    vm.expectRevert("FPMMFactory: CREATEX_BYTECODE_HASH_MISMATCH");
    factoryCelo = new FPMMFactory(false);
  }

  function test_initialize_shouldSetOwnerToGovernance() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.prank(deployer);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    assertEq(factoryCelo.owner(), governanceCelo);
  }

  function test_initialize_whenOracleAdapterIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(address(0), proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
  }

  function test_initialize_whenProxyAdminIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(oracleAdapterCelo, address(0), governanceCelo, address(fpmmImplementationCelo));
  }

  function test_initialize_whenFPMMImplementationIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(0));
  }

  function test_initialize_whenGovernanceIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, address(0), address(fpmmImplementationCelo));
  }

  function test_initialized_shouldSetVariablesAndEmitEvents() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);

    vm.expectEmit();
    emit ProxyAdminSet(proxyAdminCelo);
    vm.expectEmit();
    emit OracleAdapterSet(oracleAdapterCelo);
    vm.expectEmit();
    emit FPMMImplementationRegistered(address(fpmmImplementationCelo));
    vm.expectEmit();
    emit GovernanceSet(governanceCelo);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    assertEq(factoryCelo.oracleAdapter(), oracleAdapterCelo);
    assertEq(factoryCelo.proxyAdmin(), proxyAdminCelo);
    assertEq(factoryCelo.isRegisteredImplementation(address(fpmmImplementationCelo)), true);
    address[] memory registeredImplementations = factoryCelo.registeredImplementations();
    assertEq(registeredImplementations.length, 1);
    assertEq(registeredImplementations[0], address(fpmmImplementationCelo));
    assertEq(factoryCelo.governance(), governanceCelo);
    assertEq(factoryCelo.owner(), governanceCelo);
  }

  function test_setOracleAdapter_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setOracleAdapter(makeAddr("New OracleAdapter"));
  }

  function test_setOracleAdapter_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setOracleAdapter(address(0));
  }

  function test_setOracleAdapter_shouldSetOracleAdapterAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    address newOracleAdapter = makeAddr("New OracleAdapter");
    vm.expectEmit();
    emit OracleAdapterSet(newOracleAdapter);
    vm.prank(governanceCelo);
    factoryCelo.setOracleAdapter(newOracleAdapter);

    assertEq(factoryCelo.oracleAdapter(), newOracleAdapter);
  }

  function test_setProxyAdmin_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setProxyAdmin(makeAddr("New ProxyAdmin"));
  }

  function test_setProxyAdmin_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setProxyAdmin(address(0));
  }

  function test_setProxyAdmin_shouldSetProxyAdminAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    address newProxyAdmin = makeAddr("New ProxyAdmin");
    vm.expectEmit();
    emit ProxyAdminSet(newProxyAdmin);
    vm.prank(governanceCelo);
    factoryCelo.setProxyAdmin(newProxyAdmin);

    assertEq(factoryCelo.proxyAdmin(), newProxyAdmin);
  }

  function test_setGovernance_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setGovernance(makeAddr("New Governance"));
  }

  function test_setGovernance_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setGovernance(address(0));
  }

  function test_setGovernance_shouldSetGovernanceAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

    address newGovernance = makeAddr("New Governance");
    vm.expectEmit();
    emit GovernanceSet(newGovernance);
    vm.prank(governanceCelo);
    factoryCelo.setGovernance(newGovernance);

    assertEq(factoryCelo.governance(), newGovernance);
    assertEq(factoryCelo.owner(), newGovernance);
  }

  function test_registerImplementation_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.registerFPMMImplementation(address(fpmmImplementationCelo));
  }

  function test_registerImplementation_whenImplementationIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.registerFPMMImplementation(address(0));
  }

  function test_registerImplementation_whenImplementationIsAlreadyRegistered_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
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
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    vm.prank(governanceCelo);
    vm.expectEmit();
    emit FPMMImplementationRegistered(makeAddr("Implementation2"));
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.stopPrank();
  }

  function test_unregisterImplementation_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 0);
  }

  function test_unregisterImplementation_whenImplementationIsNotRegistered_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_NOT_REGISTERED");
    vm.prank(governanceCelo);
    factoryCelo.unregisterFPMMImplementation(makeAddr("Implementation2"), 0);
  }

  function test_unregisterImplemenattion_whenIndexIsOutOfBounds_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    vm.expectRevert("FPMMFactory: INDEX_OUT_OF_BOUNDS");
    vm.prank(governanceCelo);
    factoryCelo.unregisterFPMMImplementation(address(fpmmImplementationCelo), 1);
  }

  function test_unregisterImplementation_whenImplementationAddressAndIndexDoNotMatch_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
    vm.startPrank(governanceCelo);
    factoryCelo.registerFPMMImplementation(makeAddr("Implementation2"));
    vm.expectRevert("FPMMFactory: IMPLEMENTATION_INDEX_MISMATCH");
    factoryCelo.unregisterFPMMImplementation(makeAddr("Implementation2"), 0);
    vm.stopPrank();
  }

  function test_unregisterImplementation_shouldUnregisterImplementationAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
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
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
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
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));

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
  address public expectedOracleAdapter;
  address public expectedProxyAdmin;
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
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, fpmmImplementationCeloAddress);
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
    assertEq(factoryCelo.getPool(expectedToken0, expectedToken1), deployedProxy);
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

    address _referenceRateFeedID = address(FPMM(deployedProxy).referenceRateFeedID());
    assertEq(_referenceRateFeedID, expectedReferenceRateFeedID);

    address oracleAdapter = address(FPMM(deployedProxy).oracleAdapter());
    assertEq(oracleAdapter, expectedOracleAdapter);
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

  function test_deployFPMM_shouldDeploySameFPMMToSameAddressOnDifferentChains() public {
    vm.selectFork(celoFork);
    vm.prank(governanceCelo);
    address celoFPMMProxy = deploy("celo");
    assertEq(celoFPMMProxy, factoryCelo.getPool(token0Celo, token1Celo));

    vm.selectFork(opFork);
    vm.prank(deployer);
    factoryOp = new FPMMFactory(false);
    factoryOp.initialize(oracleAdapterOp, proxyAdminOp, governanceOp, fpmmImplementationOpAddress);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Op);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Op);

    assertEq(address(factoryOp), address(factoryCelo));

    vm.prank(governanceOp);
    address opFPMMProxy = deploy("op");
    assertEq(opFPMMProxy, factoryOp.getPool(token0Op, token1Op));

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
    expectedOracleAdapter = oracleAdapterCelo;
    expectedProxyAdmin = proxyAdminCelo;
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
    expectedOracleAdapter = makeAddr("Custom OracleAdapter");
    expectedProxyAdmin = makeAddr("Custom Proxy Admin");
    expectedGovernance = makeAddr("Custom Governance");
    expectedReferenceRateFeedID = referenceRateFeedID;
  }

  function deploy(string memory chain) internal override returns (address) {
    if (keccak256(abi.encode(chain)) == keccak256(abi.encode("celo"))) {
      return
        factoryCelo.deployFPMM(
          fpmmImplementationCeloAddress,
          expectedOracleAdapter,
          expectedProxyAdmin,
          expectedGovernance,
          token0Celo,
          token1Celo,
          referenceRateFeedID
        );
    } else if (keccak256(abi.encode(chain)) == keccak256(abi.encode("op"))) {
      return
        factoryOp.deployFPMM(
          fpmmImplementationOpAddress,
          expectedOracleAdapter,
          expectedProxyAdmin,
          expectedGovernance,
          token0Op,
          token1Op,
          referenceRateFeedID
        );
    } else {
      return address(0);
    }
  }

  function test_deployFPMM_whenCustomOracleAdapterIsZeroAddress_shouldRevert() public {
    expectedOracleAdapter = address(0);
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
    factoryCelo.initialize(oracleAdapterCelo, proxyAdminCelo, governanceCelo, address(fpmmImplementationCelo));
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
    assertEq(factoryCelo.getPool(lowerToken, higherToken), deployedProxy);
    assertEq(factoryCelo.getPool(higherToken, lowerToken), deployedProxy); // Should not exist
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
    assertEq(factoryCelo.getPool(lowerToken, higherToken), deployedProxy);
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

    assertEq(factoryCelo.getPool(lowerToken, higherToken), deployedProxy);
    assertEq(factoryCelo.getPool(higherToken, lowerToken), deployedProxy);

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
    assertEq(factoryCelo.getPool(tokenA, tokenB), proxyAB1);
    assertEq(factoryCelo.getPool(tokenB, tokenC), proxyBC1);

    // Verify reverse mappings exist
    assertEq(factoryCelo.getPool(tokenB, tokenA), proxyAB1);
    assertEq(factoryCelo.getPool(tokenC, tokenB), proxyBC1);

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
