// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { IFPMM } from "contracts/interfaces/IFPMM.sol";
import { IOracleAdapter } from "contracts/interfaces/IOracleAdapter.sol";
import { TestERC20 } from "test/utils/mocks/TestERC20.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { Router } from "contracts/swap/router/Router.sol";
import { ProxyAdmin } from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import { FactoryRegistry } from "contracts/swap/FactoryRegistry.sol";

/**
 * @title FPMMBaseIntegration
 * @notice Base contract for FPMM integration tests
 * @dev This base contract is used to simplify the implementation of integration tests for FPMM.
 * It provides common setup functions and state variables for the tests.
 */
contract FPMMBaseIntegration is Test {
  FPMMFactory public factory;
  Router public router;
  FPMM public fpmmImplementation;

  // Test tokens
  TestERC20 public tokenA;
  TestERC20 public tokenB;
  TestERC20 public tokenC;
  ProxyAdmin public proxyAdmin;
  FactoryRegistry public factoryRegistry;

  // Test accounts
  address public alice = makeAddr("alice");
  address public bob = makeAddr("bob");
  address public charlie = makeAddr("charlie");

  // External addresses TODO: should be replaced with real contracts
  address public referenceRateFeedID = makeAddr("referenceRateFeedID");
  address public oracleAdapter = makeAddr("oracleAdapter");

  address public governance = makeAddr("governance");
  address public forwarder = address(0);
  address public proxyAdminOwner = makeAddr("ProxyAdminOwner");

  // Test environment
  uint256 public celoFork = vm.createFork("https://forno.celo.org");

  // ============ SETUP ============

  function setUp() public virtual {
    vm.selectFork(celoFork);

    _deployContracts();
    _setupMocks();
    _fundTestAccounts();
  }

  // ============ INTERNAL FUNCTIONS ============

  function _deployContracts() internal {
    // Deploy test tokens
    tokenA = new TestERC20("TokenA", "TKA");
    tokenB = new TestERC20("TokenB", "TKB");
    tokenC = new TestERC20("TokenC", "TKC");

    // Deploy core contracts
    factory = new FPMMFactory(false);
    fpmmImplementation = new FPMM(true);

    // This prank should not be necessary. The owner of the ProxyAdmin could very well be address(this).
    // However, deploying the proxy admin as (this) will change the test contract's nonce and consequently will affect
    // the addresses of all subsequently deployed contracts. This should be perfectly fine but in their current state
    // some tests will break because we have some assumptions about the return values of _sortTokens().
    vm.startPrank(proxyAdminOwner);
    proxyAdmin = new ProxyAdmin();
    factoryRegistry = new FactoryRegistry(false);
    vm.stopPrank();

    router = new Router(forwarder, address(factoryRegistry), address(factory));

    factory.initialize(oracleAdapter, address(proxyAdmin), governance, address(fpmmImplementation));
    factoryRegistry.initialize(address(factory), governance);
  }

  function _setupMocks() internal {
    vm.mockCall(
      address(oracleAdapter),
      abi.encodeWithSelector(IOracleAdapter.getFXRateIfValid.selector, referenceRateFeedID),
      abi.encode(1e18, 1e18)
    );
  }

  function _fundTestAccounts() internal {
    deal(address(tokenA), alice, 1000e18);
    deal(address(tokenB), alice, 1000e18);
    deal(address(tokenC), alice, 1000e18);

    deal(address(tokenA), bob, 1000e18);
    deal(address(tokenB), bob, 1000e18);
    deal(address(tokenC), bob, 1000e18);

    deal(address(tokenA), charlie, 1000e18);
    deal(address(tokenB), charlie, 1000e18);
    deal(address(tokenC), charlie, 1000e18);

    vm.startPrank(alice);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
    tokenC.approve(address(router), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(bob);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
    tokenC.approve(address(router), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(charlie);
    tokenA.approve(address(router), type(uint256).max);
    tokenB.approve(address(router), type(uint256).max);
    tokenC.approve(address(router), type(uint256).max);
    vm.stopPrank();
  }

  function _sortTokens(address tokenA_, address tokenB_) internal pure returns (address token0, address token1) {
    if (tokenA_ < tokenB_) {
      return (tokenA_, tokenB_);
    } else {
      return (tokenB_, tokenA_);
    }
  }

  function _addInitialLiquidity(address token0, address token1, address fpmm) internal {
    deal(token0, fpmm, 1000 * 10 ** TestERC20(token0).decimals());
    deal(token1, fpmm, 1000 * 10 ** TestERC20(token1).decimals());

    // Mint liquidity tokens
    IFPMM(fpmm).mint(makeAddr("LP"));
  }

  function _deployFPMM(address token0, address token1) internal returns (address fpmm) {
    vm.prank(governance);
    fpmm = factory.deployFPMM(address(fpmmImplementation), address(token0), address(token1), referenceRateFeedID);
  }
}
