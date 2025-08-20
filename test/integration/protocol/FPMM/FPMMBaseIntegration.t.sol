// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable var-name-mixedcase
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";
import { FPMM } from "contracts/swap/FPMM.sol";
import { ERC20DecimalsMock } from "openzeppelin-contracts-next/contracts/mocks/ERC20DecimalsMock.sol";
import { IERC20 } from "openzeppelin-contracts-next/contracts/token/ERC20/IERC20.sol";
import { ISortedOracles } from "contracts/interfaces/ISortedOracles.sol";
import { IBreakerBox } from "contracts/interfaces/IBreakerBox.sol";
import { TestERC20 } from "test/utils/mocks/TestERC20.sol";
import { FPMMFactory } from "contracts/swap/FPMMFactory.sol";

contract FPMMBaseIntegration is Test {
  FPMMFactory public factory;
  FPMM public fpmmImplementation;

  // Test tokens
  TestERC20 public tokenA;
  TestERC20 public tokenB;
  TestERC20 public tokenC;

  // Test accounts
  address public alice = makeAddr("alice");
  address public bob = makeAddr("bob");
  address public charlie = makeAddr("charlie");

  // External addresses TODO: should be replaced with real contracts
  address public referenceRateFeedID = makeAddr("referenceRateFeedID");
  address public sortedOracles = makeAddr("sortedOracles");
  address public breakerBox = makeAddr("breakerBox");
  address public proxyAdmin = makeAddr("proxyAdmin");
  address public governance = makeAddr("governance");

  // Test environment
  uint256 public celoFork = vm.createFork("https://forno.celo.org");

  // ============ SETUP ============

  function setUp() public virtual {
    vm.warp(60 * 60 * 24 * 10); // Start at a non-zero timestamp
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

    factory.initialize(sortedOracles, proxyAdmin, breakerBox, governance, address(fpmmImplementation));
  }

  function _setupMocks() internal {
    // Mock sorted oracles to return a rate
    vm.mockCall(
      address(sortedOracles),
      abi.encodeWithSelector(ISortedOracles.medianRate.selector, referenceRateFeedID),
      abi.encode(1e18, 1e18)
    );

    // Mock breaker box to return a trading mode
    vm.mockCall(
      address(breakerBox),
      abi.encodeWithSelector(IBreakerBox.getRateFeedTradingMode.selector, referenceRateFeedID),
      abi.encode(0) // TRADING_MODE_BIDIRECTIONAL
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
  }

  function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
    if (tokenA < tokenB) {
      return (tokenA, tokenB);
    } else {
      return (tokenB, tokenA);
    }
  }
}
