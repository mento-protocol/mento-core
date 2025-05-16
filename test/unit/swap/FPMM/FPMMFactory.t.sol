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
  event FPMMDeployed(address indexed token0, address indexed token1, address fpmm);
  event FPMMImplementationDeployed(address indexed implementation);
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

  // Optimism
  uint256 public opFork;
  address public token0Op;
  address public token1Op;
  address public sortedOraclesOp;
  address public breakerBoxOp;
  address public proxyAdminOp;
  address public governanceOp;
  FPMMFactory public factoryOp;

  function setUp() public virtual {
    createX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    deployer = makeAddr("Deployer");
    referenceRateFeedID = makeAddr("token0/token1");

    celoFork = vm.createFork("https://forno.celo.org");
    token0Celo = makeAddr("Token 0 Celo");
    token1Celo = makeAddr("Token 1 Celo");
    sortedOraclesCelo = makeAddr("SortedOracles Celo");
    breakerBoxCelo = makeAddr("BreakerBox Celo");
    proxyAdminCelo = makeAddr("ProxyAdmin Celo");
    governanceCelo = makeAddr("Governance Celo");

    opFork = vm.createFork("https://mainnet.optimism.io");
    token0Op = makeAddr("Token 0 Optimism");
    token1Op = makeAddr("Token 1 Optimism");
    sortedOraclesOp = makeAddr("SortedOracles Optimism");
    breakerBoxOp = makeAddr("BreakerBox Optimism");
    proxyAdminOp = makeAddr("ProxyAdmin Optimism");
    governanceOp = makeAddr("Governance Optimism");
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
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);
  }
  function test_constructor_whenDisableFalse_shouldNotDisableInitializers() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);
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
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);
    assertEq(factoryCelo.owner(), governanceCelo);
  }

  function test_initialize_whenSortedOraclesIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(address(0), proxyAdminCelo, breakerBoxCelo, governanceCelo);
  }

  function test_initialize_whenProxyAdminIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(sortedOraclesCelo, address(0), breakerBoxCelo, governanceCelo);
  }

  function test_initialize_whenBreakerBoxIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, address(0), governanceCelo);
  }

  function test_initialize_whenGovernanceIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, address(0));
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
    emit GovernanceSet(governanceCelo);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    assertEq(factoryCelo.sortedOracles(), sortedOraclesCelo);
    assertEq(factoryCelo.proxyAdmin(), proxyAdminCelo);
    assertEq(factoryCelo.breakerBox(), breakerBoxCelo);
    assertEq(factoryCelo.governance(), governanceCelo);
    assertEq(factoryCelo.owner(), governanceCelo);
  }

  function test_setSortedOracles_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setSortedOracles(makeAddr("New SortedOracles"));
  }

  function test_setSortedOracles_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setSortedOracles(address(0));
  }

  function test_setSortedOracles_shouldSetSortedOraclesAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

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
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setProxyAdmin(makeAddr("New ProxyAdmin"));
  }

  function test_setProxyAdmin_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setProxyAdmin(address(0));
  }

  function test_setProxyAdmin_shouldSetProxyAdminAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

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
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setBreakerBox(makeAddr("New BreakerBox"));
  }

  function test_setBreakerBox_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setBreakerBox(address(0));
  }

  function test_setBreakerBox_shouldSetBreakerBoxAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

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
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setGovernance(makeAddr("New Governance"));
  }

  function test_setGovernance_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    vm.prank(governanceCelo);
    factoryCelo.setGovernance(address(0));
  }

  function test_setGovernance_shouldSetGovernanceAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    address newGovernance = makeAddr("New Governance");
    vm.expectEmit();
    emit GovernanceSet(newGovernance);
    vm.prank(governanceCelo);
    factoryCelo.setGovernance(newGovernance);

    assertEq(factoryCelo.governance(), newGovernance);
  }

  function test_getOrPrecomputeAddress_whenContractsAreNotDeployed_shouldReturnCorrectPrecomputedAddresses() public {
    vm.selectFork(celoFork);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Celo);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Celo);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);

    address precomputedImplementation = factoryCelo.getOrPrecomputeImplementationAddress();
    address precomputedProxy = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);

    address implementation = factoryCelo.fpmmImplementation();
    assertEq(implementation, address(0));

    vm.prank(governanceCelo);
    (address deployedImplementation, address deployedProxy) = factoryCelo.deployFPMM(
      token0Celo,
      token1Celo,
      referenceRateFeedID
    );

    assertEq(deployedImplementation, precomputedImplementation);
    assertEq(deployedProxy, precomputedProxy);
  }
}

contract FPMMFactoryTest_DeployFPMMUnitTests is FPMMFactoryTest {
  function setUp() public override {
    super.setUp();

    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Celo);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Celo);
  }

  function test_deployFPMM_whenCallerIsNotOwner_shouldRevert() public {
    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.deployFPMM(token0Celo, token1Celo, referenceRateFeedID);
  }

  function test_deployFPMM_whenToken0OrToken1IsZeroAddress_shouldRevert() public {
    vm.startPrank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.deployFPMM(address(0), token1Celo, referenceRateFeedID);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.deployFPMM(token0Celo, address(0), referenceRateFeedID);
    vm.stopPrank();
  }

  function test_deployFPMM_whenReferenceRateFeedIDIsZeroAddress_shouldRevert() public {
    vm.startPrank(governanceCelo);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.deployFPMM(token0Celo, token1Celo, address(0));
    vm.stopPrank();
  }

  function test_deployFPMM_whenToken0AndToken1AreSame_shouldRevert() public {
    vm.startPrank(governanceCelo);
    vm.expectRevert("FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");
    factoryCelo.deployFPMM(token0Celo, token0Celo, referenceRateFeedID);
    vm.stopPrank();
  }

  function test_deployFPMM_whenFirstTimeDeploying_shouldDeployFPMMImplementationAndEmitEvent() public {
    vm.startPrank(governanceCelo);
    assertEq(factoryCelo.fpmmImplementation(), address(0));

    address expectedFPMMImplementation = factoryCelo.getOrPrecomputeImplementationAddress();
    vm.expectEmit();
    emit FPMMImplementationDeployed(expectedFPMMImplementation);
    factoryCelo.deployFPMM(token0Celo, token1Celo, referenceRateFeedID);

    assertEq(factoryCelo.fpmmImplementation(), expectedFPMMImplementation);

    vm.expectRevert("Initializable: contract is already initialized");
    FPMM(expectedFPMMImplementation).initialize(
      token0Celo,
      token1Celo,
      sortedOraclesCelo,
      referenceRateFeedID,
      breakerBoxCelo,
      governanceCelo
    );
    vm.stopPrank();
  }

  function test_deployFPMM_whenAlreadyDeployed_shouldNotDeploySecondImplementation() public {
    vm.startPrank(governanceCelo);
    factoryCelo.deployFPMM(token0Celo, token1Celo, referenceRateFeedID);
    address implementation = factoryCelo.fpmmImplementation();
    assertTrue(implementation != address(0));

    factoryCelo.deployFPMM(token1Celo, token0Celo, referenceRateFeedID);
    assertEq(factoryCelo.fpmmImplementation(), implementation);
    vm.stopPrank();
  }

  function test_deployFPMM_shouldDeployFPMMProxyAndEmitEvent() public {
    vm.startPrank(governanceCelo);

    address expectedProxyAddress = factoryCelo.getOrPrecomputeProxyAddress(token0Celo, token1Celo);

    vm.expectEmit();
    emit FPMMDeployed(token0Celo, token1Celo, expectedProxyAddress);
    factoryCelo.deployFPMM(token0Celo, token1Celo, referenceRateFeedID);

    address proxy = address(factoryCelo.deployedFPMMs(token0Celo, token1Celo));
    assertEq(proxy, expectedProxyAddress);
    vm.stopPrank();

    // if not pranked, the proxy will revert
    vm.startPrank(proxyAdminCelo);
    address proxyAdmin = ITransparentUpgradeableProxy(proxy).admin();
    assertEq(proxyAdmin, factoryCelo.proxyAdmin());

    address implementation = ITransparentUpgradeableProxy(proxy).implementation();
    assertEq(implementation, factoryCelo.fpmmImplementation());
    vm.stopPrank();

    // test that the proxy is initialized correctly
    address owner = FPMM(proxy).owner();
    assertEq(owner, governanceCelo);

    address token0 = FPMM(proxy).token0();
    assertEq(token0, token0Celo);

    address token1 = FPMM(proxy).token1();
    assertEq(token1, token1Celo);

    address breakerBox = address(FPMM(proxy).breakerBox());
    assertEq(breakerBox, breakerBoxCelo);

    address _referenceRateFeedID = address(FPMM(proxy).referenceRateFeedID());
    assertEq(_referenceRateFeedID, referenceRateFeedID);

    address sortedOracles = address(FPMM(proxy).sortedOracles());
    assertEq(sortedOracles, sortedOraclesCelo);
  }

  function test_deployFPMM_whenSameSaltIsUsedByDifferentAddress_shouldNotDeployToSameAddress() public {
    vm.selectFork(celoFork);
    address alice = makeAddr("Alice");

    bytes32 implementationSalt = bytes32(abi.encodePacked(address(factoryCelo), hex"00", bytes11("FPMM_IMPLEM")));
    bytes memory implementationBytecode = abi.encodePacked(type(FPMM).creationCode, abi.encode(true));

    vm.startPrank(alice);
    address aliceFPMMImplementation = ICreateX(createX).deployCreate3(implementationSalt, implementationBytecode);

    bytes11 customProxySalt = bytes11(
      uint88(uint256(keccak256(abi.encodePacked(IERC20(token0Celo).symbol(), IERC20(token1Celo).symbol()))))
    );
    bytes32 proxySalt = bytes32(abi.encodePacked(address(factoryCelo), hex"00", customProxySalt));
    bytes memory proxyInitData = abi.encodeWithSelector(
      FPMM.initialize.selector,
      token0Celo,
      token1Celo,
      sortedOraclesCelo,
      referenceRateFeedID,
      breakerBoxCelo,
      governanceCelo
    );
    bytes memory proxyBytecode = abi.encodePacked(
      type(FPMMProxy).creationCode,
      abi.encode(aliceFPMMImplementation, proxyAdminCelo, proxyInitData)
    );

    address aliceFPMMProxy = ICreateX(createX).deployCreate3(proxySalt, proxyBytecode);
    vm.stopPrank();

    vm.prank(governanceCelo);
    factoryCelo.deployFPMM(token0Celo, token1Celo, referenceRateFeedID);

    address factoryImplementation = factoryCelo.fpmmImplementation();
    address factoryProxy = address(factoryCelo.deployedFPMMs(token0Celo, token1Celo));
    assertNotEq(factoryImplementation, aliceFPMMImplementation);
    assertNotEq(factoryProxy, aliceFPMMProxy);
  }
}

contract FPMMFactoryTest_DeployFPMMCrossChain is FPMMFactoryTest {
  function setUp() public override {
    super.setUp();
    vm.selectFork(celoFork);

    vm.prank(deployer);
    factoryCelo = new FPMMFactory(false);

    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo, breakerBoxCelo, governanceCelo);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Celo);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Celo);

    vm.selectFork(opFork);

    vm.prank(deployer);
    factoryOp = new FPMMFactory(false);
    factoryOp.initialize(sortedOraclesOp, proxyAdminOp, breakerBoxOp, governanceOp);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0Op);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1Op);
  }

  function test_deployFPMM_shouldDeploySameFPMMToSameAddressOnDifferentChains() public {
    // factoryCelo and factoryOp need to be deployed to the same address on both chains
    // in order to have same FPMM address on both chains due to CREATEX permissioned deploy protection
    assertEq(address(factoryCelo), address(factoryOp));
    vm.selectFork(celoFork);

    vm.prank(governanceCelo);
    factoryCelo.deployFPMM(token0Celo, token1Celo, referenceRateFeedID);

    address celoFPMMImplementation = factoryCelo.fpmmImplementation();
    address celoFPMMProxy = address(factoryCelo.deployedFPMMs(token0Celo, token1Celo));

    vm.selectFork(opFork);

    vm.prank(governanceOp);
    factoryOp.deployFPMM(token0Op, token1Op, referenceRateFeedID);

    address opFPMMImplementation = factoryOp.fpmmImplementation();
    address opFPMMProxy = address(factoryOp.deployedFPMMs(token0Op, token1Op));

    vm.assertEq(celoFPMMImplementation, opFPMMImplementation, "FPMM implementations should be the same");
    vm.assertEq(celoFPMMProxy, opFPMMProxy, "FPMM proxies should be the same");
  }
}
