// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Test } from "mento-std/Test.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { VirtualPoolFactory } from "contracts/swap/virtual/VirtualPoolFactory.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { IVirtualPoolFactory } from "contracts/interfaces/IVirtualPoolFactory.sol";
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";

contract VirtualPoolFactoryTest is Test {
  event VirtualPoolDeployed(address indexed pool, address indexed token0, address indexed token1);

  VirtualPoolFactory public factory;
  address public tokenA;
  address public tokenB;
  address public broker = makeAddr("Broker");
  address public exchangeProvider = makeAddr("ExchangeProvider");

  function setUp() public {
    tokenA = address(new MockERC20("Token A", "TOKA", 18));
    tokenB = address(new MockERC20("Token B", "TOKB", 18));
    factory = new VirtualPoolFactory();
    _setupMocks();
  }

  function test_deployFactory_shouldInitializeCorrectly() public {
    assertEq(factory.isPool(makeAddr("pool")), false);
    assertEq(factory.getOrPrecomputeProxyAddress(tokenA, tokenB), address(0));
    assertEq(factory.getPool(tokenA, tokenB), address(0));
    assertEq(factory.owner(), address(this));
  }

  function test_deployPool_shouldFailIfNotOwner() public {
    vm.startPrank(makeAddr("literallyAnyone"));
    vm.expectRevert("Ownable: caller is not the owner");
    factory.deployVirtualPool(address(0), bytes32(0));
    vm.stopPrank();
  }

  function test_deployPool_whenWrongExchangeProvider_noBrokerSelector_shouldRevert() public {
    address wrongExchangeProvider = makeAddr("wrongExchangeProvider");
    vm.expectRevert(IVirtualPoolFactory.InvalidExchangeProvider.selector);
    factory.deployVirtualPool(wrongExchangeProvider, bytes32(0));
  }

  function test_deployPool_whenWrongExchangeProvider_noBroker_shouldRevert() public {
    address wrongExchangeProvider = makeAddr("wrongExchangeProvider");
    vm.mockCall(wrongExchangeProvider, abi.encodeWithSelector(IBiPoolManager.broker.selector), abi.encode(address(0)));
    vm.expectRevert(IVirtualPoolFactory.InvalidExchangeProvider.selector);
    factory.deployVirtualPool(wrongExchangeProvider, bytes32(0));
  }

  function test_deployPool_whenWrongExchangeProvider_noExchanges_shouldRevert() public {
    address wrongExchangeProvider = makeAddr("wrongExchangeProvider");
    address fakeBroker = makeAddr("fakeBroker");
    vm.mockCall(wrongExchangeProvider, abi.encodeWithSelector(IBiPoolManager.broker.selector), abi.encode(fakeBroker));
    vm.expectRevert(IVirtualPoolFactory.InvalidExchangeProvider.selector);
    factory.deployVirtualPool(wrongExchangeProvider, bytes32(0));
  }

  function test_deployPool_whenWrongExchangeProvider_noExchange_shouldRevert() public {
    address wrongExchangeProvider = makeAddr("wrongExchangeProvider");
    address fakeBroker = makeAddr("fakeBroker");
    vm.mockCall(wrongExchangeProvider, abi.encodeWithSelector(IBiPoolManager.broker.selector), abi.encode(fakeBroker));
    vm.mockCall(
      wrongExchangeProvider,
      abi.encodeWithSelector(IBiPoolManager.exchanges.selector),
      abi.encode(_makeQuickExchange(address(0), makeAddr("someToken")))
    );
    vm.expectRevert(IVirtualPoolFactory.InvalidExchangeId.selector);
    factory.deployVirtualPool(wrongExchangeProvider, bytes32(0));
  }

  function test_deployPool_shouldEmitEventAndSavePool() public {
    vm.expectEmit(false, true, true, true, address(factory));
    (address t0, address t1) = (tokenA < tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
    emit VirtualPoolDeployed(address(0), t0, t1);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));
    assertEq(factory.isPool(pool), true);
    assertEq(factory.getPool(tokenA, tokenB), pool);
    assertEq(factory.getPool(tokenB, tokenA), pool);
    assertEq(factory.getOrPrecomputeProxyAddress(tokenA, tokenB), pool);
    assertEq(factory.getOrPrecomputeProxyAddress(tokenB, tokenA), pool);
  }

  function test_deployPool_whenPairAlreadyExists_shouldRevert() public {
    factory.deployVirtualPool(exchangeProvider, bytes32(0));
    vm.expectRevert(IVirtualPoolFactory.VirtualPoolAlreadyExistsForThisPair.selector);
    factory.deployVirtualPool(exchangeProvider, bytes32(0));
    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBiPoolManager.exchanges.selector),
      abi.encode(_makeQuickExchange(tokenB, tokenA))
    );
    vm.expectRevert(IVirtualPoolFactory.VirtualPoolAlreadyExistsForThisPair.selector);
    factory.deployVirtualPool(exchangeProvider, bytes32(0));
  }

  function _bpsToFraction(uint256 bps) internal pure returns (FixidityLib.Fraction memory) {
    return FixidityLib.newFixedFraction(bps, 10000);
  }

  function _setupMocks() internal {
    vm.mockCall(exchangeProvider, abi.encodeWithSelector(IBiPoolManager.broker.selector), abi.encode(broker));
    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBiPoolManager.exchanges.selector),
      abi.encode(_makeQuickExchange(tokenA, tokenB))
    );
  }

  function _makeQuickExchange(address asset0, address asset1) internal returns (IBiPoolManager.PoolExchange memory) {
    return
      IBiPoolManager.PoolExchange({
        asset0: asset0,
        asset1: asset1,
        pricingModule: IPricingModule(makeAddr("pricingModule")),
        bucket0: 100e18,
        bucket1: 100e18,
        lastBucketUpdate: block.timestamp,
        config: IBiPoolManager.PoolConfig({
          spread: _bpsToFraction(30),
          referenceRateFeedID: makeAddr("referenceRate"),
          referenceRateResetFrequency: 1,
          minimumReports: 1,
          stablePoolResetSize: 1
        })
      });
  }
}
