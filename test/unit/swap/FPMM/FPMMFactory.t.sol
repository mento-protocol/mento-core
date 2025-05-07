// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { ICreateX } from "contracts/interfaces/ICreateX.sol";
contract FPMMFactoryTest is Test {
  /* ------- Events from FPMMFactory ------- */

  event FPMMDeployed(address indexed token0, address indexed token1, address fpmm);
  event FPMMImplementationDeployed(address indexed implementation);
  event ProxyAdminSet(address indexed proxyAdmin);
  event SortedOraclesSet(address indexed sortedOracles);

  /* --------------------------------------- */

  address public deployer;
  address public createX;

  // Tokens:
  address public token0;
  address public token1;

  // Celo
  uint256 public celoFork;
  FPMMFactory public factoryCelo;
  address public sortedOraclesCelo;
  address public proxyAdminCelo;

  // Optimism
  uint256 public opFork;
  FPMMFactory public factoryOp;
  address public sortedOraclesOp;
  address public proxyAdminOp;

  function setUp() public virtual {
    celoFork = vm.createFork("https://forno.celo.org");
    opFork = vm.createFork("https://mainnet.optimism.io");

    token0 = makeAddr("Token 0");
    token1 = makeAddr("Token 1");
    deployer = makeAddr("Deployer");
    createX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
  }

  function test_deployFPMM() public {
    vm.selectFork(celoFork);
    vm.assertEq(vm.activeFork(), celoFork);
    console.log("chainId", block.chainid);

    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1);

    sortedOraclesCelo = makeAddr("SortedOracles");
    proxyAdminCelo = makeAddr("ProxyAdmin");

    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOraclesCelo, proxyAdminCelo);
    factoryCelo.deployFPMM(token0, token1);

    address celoFPMMImplementation = factoryCelo.fpmmImplementation();
    address celoFPMMProxy = address(factoryCelo.deployedFPMMs(token0, token1));

    FPMM celoFPMM = FPMM(factoryCelo.deployedFPMMs(token0, token1));
    assertEq(celoFPMM.token0(), token0);
    assertEq(celoFPMM.token1(), token1);
    assertEq(address(celoFPMM.sortedOracles()), sortedOraclesCelo);
    assertEq(factoryCelo.proxyAdmin(), proxyAdminCelo);

    vm.selectFork(opFork);
    vm.assertEq(vm.activeFork(), opFork);
    console.log("chainId", block.chainid);

    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), token0);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), token1);

    sortedOraclesOp = makeAddr("SortedOracles");
    proxyAdminOp = makeAddr("ProxyAdmin");

    factoryOp = new FPMMFactory(false);

    factoryOp.initialize(sortedOraclesOp, proxyAdminOp);
    factoryOp.deployFPMM(token0, token1);

    address opFPMMImplementation = factoryOp.fpmmImplementation();
    address opFPMMProxy = address(factoryOp.deployedFPMMs(token0, token1));

    FPMM opFPMM = FPMM(factoryOp.deployedFPMMs(token0, token1));
    assertEq(opFPMM.token0(), token0);
    assertEq(opFPMM.token1(), token1);
    assertEq(address(opFPMM.sortedOracles()), sortedOraclesOp);
    assertEq(factoryOp.proxyAdmin(), proxyAdminOp);

    console.log("SortedOracles Celo", address(sortedOraclesCelo));
    console.log("SortedOracles Optimism", address(sortedOraclesOp));
    console.log("ProxyAdmin Celo", address(proxyAdminCelo));
    console.log("ProxyAdmin Optimism", address(proxyAdminOp));
    console.log("token0", address(token0));
    console.log("token1", address(token1));

    vm.assertEq(celoFPMMImplementation, opFPMMImplementation, "FPMM implementations should be the same");
    console.log("celoFPMMImplementation", address(celoFPMMImplementation));
    console.log("opFPMMImplementation", address(opFPMMImplementation));
    vm.assertEq(celoFPMMProxy, opFPMMProxy, "FPMM proxies should be the same");
    console.log("celoFPMMProxy", address(celoFPMMProxy));
    console.log("opFPMMProxy", address(opFPMMProxy));
  }
}

contract FPMMFactoryTest_InitializerSettersGetters is FPMMFactoryTest {
  address public sortedOracles;
  address public proxyAdmin;

  function setUp() public override {
    super.setUp();
    sortedOracles = makeAddr("SortedOracles");
    proxyAdmin = makeAddr("ProxyAdmin");
  }

  function test_constructor_whenDisableTrue_shouldDisableInitializers() public {
    vm.selectFork(celoFork); // select celo fork to have CREATEX deployed
    factoryCelo = new FPMMFactory(true);
    vm.expectRevert("Initializable: contract is already initialized");
    factoryCelo.initialize(sortedOracles, proxyAdmin);
  }
  function test_constructor_whenDisableFalse_shouldNotDisableInitializers() public {
    vm.selectFork(celoFork); // select celo fork to have CREATEX deployed
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOracles, proxyAdmin);
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
    factoryCelo.initialize(sortedOracles, proxyAdmin);
    assertEq(factoryCelo.owner(), deployer);
  }

  function test_initialize_whenSortedOraclesIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(address(0), proxyAdmin);
  }

  function test_initialize_whenProxyAdminIsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.initialize(sortedOracles, address(0));
  }

  function test_initialized_shouldSetSortedOraclesAndProxyAdminAndEmitEvents() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);

    vm.expectEmit();
    emit SortedOraclesSet(sortedOracles);
    vm.expectEmit();
    emit ProxyAdminSet(proxyAdmin);
    factoryCelo.initialize(sortedOracles, proxyAdmin);

    assertEq(factoryCelo.sortedOracles(), sortedOracles);
    assertEq(factoryCelo.proxyAdmin(), proxyAdmin);
  }

  function test_setSortedOracles_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOracles, proxyAdmin);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setSortedOracles(makeAddr("New SortedOracles"));
  }

  function test_setSortedOracles_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOracles, proxyAdmin);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.setSortedOracles(address(0));
  }

  function test_setSortedOracles_shouldSetSortedOraclesAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOracles, proxyAdmin);

    address newSortedOracles = makeAddr("New SortedOracles");
    vm.expectEmit();
    emit SortedOraclesSet(newSortedOracles);
    factoryCelo.setSortedOracles(newSortedOracles);

    assertEq(factoryCelo.sortedOracles(), newSortedOracles);
  }

  function test_setProxyAdmin_whenCallerIsNotOwner_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOracles, proxyAdmin);

    vm.expectRevert("Ownable: caller is not the owner");
    vm.prank(makeAddr("Not Owner"));
    factoryCelo.setProxyAdmin(makeAddr("New ProxyAdmin"));
  }

  function test_setProxyAdmin_whenZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOracles, proxyAdmin);

    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factoryCelo.setProxyAdmin(address(0));
  }

  function test_setProxyAdmin_shouldSetProxyAdminAndEmitEvent() public {
    vm.selectFork(celoFork);
    factoryCelo = new FPMMFactory(false);
    factoryCelo.initialize(sortedOracles, proxyAdmin);

    address newProxyAdmin = makeAddr("New ProxyAdmin");
    vm.expectEmit();
    emit ProxyAdminSet(newProxyAdmin);
    factoryCelo.setProxyAdmin(newProxyAdmin);

    assertEq(factoryCelo.proxyAdmin(), newProxyAdmin);
  }
}

contract FPMMFactoryTest_DeployFPMMUnitTests is FPMMFactoryTest {
  address public sortedOracles;
  address public proxyAdmin;

  address Token0;
  address Token1;

  FPMMFactory public factory;

  function setUp() public override {
    super.setUp();
    sortedOracles = makeAddr("SortedOracles");
    proxyAdmin = makeAddr("ProxyAdmin");
    Token0 = makeAddr("Token 0");
    Token1 = makeAddr("Token 1");

    vm.selectFork(celoFork);
    factory = new FPMMFactory(false);
    factory.initialize(sortedOracles, proxyAdmin);
    deployCodeTo("ERC20", abi.encode("Token 0", "T0"), Token0);
    deployCodeTo("ERC20", abi.encode("Token 1", "T1"), Token1);
  }
  function test_deployFPMM_whenToken0OrToken1IsZeroAddress_shouldRevert() public {
    vm.selectFork(celoFork);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.deployFPMM(address(0), Token1);
    vm.expectRevert("FPMMFactory: ZERO_ADDRESS");
    factory.deployFPMM(token0, address(0));
  }

  function test_deployFPMM_whenToken0AndToken1AreSame_shouldRevert() public {
    vm.selectFork(celoFork);
    vm.expectRevert("FPMMFactory: IDENTICAL_TOKEN_ADDRESSES");
    factory.deployFPMM(Token0, Token0);
  }

  function test_deployFPMM_whenFirstTimeDeploying_shouldDeployFPMMImplementationAndEmitEvent() public {
    vm.selectFork(celoFork);

    assertEq(factory.fpmmImplementation(), address(0));

    // address expectedFPMMImplementation = ICreateX(createX).computeCreate3Address(
    //   keccak256("FPMM_IMPLEMENTATION"),
    //   address(factory)
    // );

    // console.log("expectedFPMMImplementation", expectedFPMMImplementation);

    factory.deployFPMM(Token0, Token1);

    // assertEq(factory.fpmmImplementation(), expectedFPMMImplementation);
  }
}
