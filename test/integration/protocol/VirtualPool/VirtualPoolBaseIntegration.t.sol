// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility, const-name-snakecase, max-states-count
pragma solidity ^0.8;

import { ProtocolTest } from "../ProtocolTest.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";
import { Router } from "contracts/swap/router/Router.sol";
import { IRouter } from "contracts/swap/router/interfaces/IRouter.sol";
import { VirtualPoolFactory } from "contracts/swap/virtual/VirtualPoolFactory.sol";
import { IFactoryRegistry } from "contracts/swap/router/interfaces/IFactoryRegistry.sol";
import { TestERC20 } from "test/utils/mocks/TestERC20.sol";

contract VirtualPoolBaseIntegration is ProtocolTest {
  FPMMFactory public fpmmFactory;
  Router public router;
  FPMM public fpmmImplementation;
  VirtualPoolFactory public vpFactory;

  // Test accounts
  address public alice = makeAddr("alice");
  address public bob = makeAddr("bob");
  address public charlie = makeAddr("charlie");

  // External addresses
  address public referenceRateFeedID = makeAddr("referenceRateFeedID");
  address public proxyAdmin = makeAddr("proxyAdmin");
  address public governance = makeAddr("governance");
  address public factoryRegistry = makeAddr("factoryRegistry");
  address public forwarder = address(0);

  // Test environment
  uint256 public celoFork = vm.createFork("https://forno.celo.org");

  function setUp() public override {
    vm.warp(60 * 60 * 24 * 10); // Start at a non-zero timestamp
    vm.selectFork(vm.createFork("https://forno.celo.org"));

    super.setUp();

    _deployVirtualPoolFactory();
    _deployV3Contracts();
    _setupMocks();
    _fundTestAccounts();
  }

  function _deployVirtualPoolFactory() internal {
    vpFactory = new VirtualPoolFactory();
  }

  function _deployV3Contracts() internal {
    // Deploy core contracts
    fpmmFactory = new FPMMFactory(false);
    fpmmImplementation = new FPMM(true);

    router = new Router(forwarder, factoryRegistry, address(fpmmFactory));

    fpmmFactory.initialize(
      address(sortedOracles),
      proxyAdmin,
      address(breakerBox),
      governance,
      address(fpmmImplementation)
    );
  }

  function _setupMocks() internal {
    // Mock factory registry to approve our pool factories
    vm.mockCall(
      factoryRegistry,
      abi.encodeWithSelector(IFactoryRegistry.isPoolFactoryApproved.selector, address(fpmmFactory)),
      abi.encode(true)
    );
    vm.mockCall(
      factoryRegistry,
      abi.encodeWithSelector(IFactoryRegistry.isPoolFactoryApproved.selector, address(vpFactory)),
      abi.encode(true)
    );
  }

  function _fundTestAccounts() internal {
    deal(address(celoToken), alice, 1000e18);

    deal(address(usdcToken), bob, 1000e18);

    deal(address(cUSDToken), charlie, 1000e18);
    deal(address(cEURToken), charlie, 1000e18);

    _approveAll(alice);
    _approveAll(bob);
    _approveAll(charlie);
  }

  function _approveAll(address approver) internal {
    vm.startPrank(approver);
    celoToken.approve(address(router), type(uint256).max);
    usdcToken.approve(address(router), type(uint256).max);
    eurocToken.approve(address(router), type(uint256).max);
    cUSDToken.approve(address(router), type(uint256).max);
    cEURToken.approve(address(router), type(uint256).max);
    eXOFToken.approve(address(router), type(uint256).max);
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
    FPMM(fpmm).mint(makeAddr("LP"));
  }

  function _deployFPMM(address token0, address token1, address rateFeedID) internal returns (address fpmm) {
    vm.prank(governance);
    fpmm = fpmmFactory.deployFPMM(address(fpmmImplementation), address(token0), address(token1), rateFeedID);
  }

  function _createV3Route(address from, address to) internal view returns (IRouter.Route memory) {
    return IRouter.Route({ from: from, to: to, factory: address(fpmmFactory) });
  }

  function _createVirtualRoute(address from, address to) internal view returns (IRouter.Route memory) {
    return IRouter.Route({ from: from, to: to, factory: address(vpFactory) });
  }
}
