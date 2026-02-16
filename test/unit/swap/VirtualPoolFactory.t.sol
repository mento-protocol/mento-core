// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";
import { VirtualPoolFactory } from "contracts/swap/virtual/VirtualPoolFactory.sol";
import { IBiPoolManager } from "contracts/interfaces/IBiPoolManager.sol";
import { IPricingModule } from "contracts/interfaces/IPricingModule.sol";
import { IVirtualPoolFactory } from "contracts/interfaces/IVirtualPoolFactory.sol";
import { FixidityLib } from "celo/contracts/common/FixidityLib.sol";
import { CreateXHelper } from "test/utils/CreateXHelper.sol";

contract VirtualPoolFactoryTest is Test, CreateXHelper {
  event VirtualPoolDeployed(address indexed pool, address indexed token0, address indexed token1);
  event PoolDeprecated(address indexed pool);

  VirtualPoolFactory public factory;
  address public tokenA;
  address public tokenB;
  address public broker = makeAddr("Broker");
  address public governance = makeAddr("Governance");
  address public exchangeProvider = makeAddr("ExchangeProvider");

  function setUp() public {
    deployCreateX();
    tokenA = address(new MockERC20("Token A", "TOKA", 18));
    tokenB = address(new MockERC20("Token B", "TOKB", 18));
    factory = new VirtualPoolFactory(governance);
    _setupMocks();
  }

  function test_deployFactory_shouldInitializeCorrectly() public {
    assertEq(factory.isPool(makeAddr("pool")), false);
    assertEq(factory.getPool(tokenA, tokenB), address(0));
    assertEq(factory.owner(), governance);
  }

  function test_deployPool_shouldFailIfNotOwner() public {
    vm.startPrank(makeAddr("literallyAnyone"));
    vm.expectRevert("Ownable: caller is not the owner");
    factory.deployVirtualPool(address(0), bytes32(0));
    vm.stopPrank();
  }

  function test_deployPool_whenWrongExchangeProvider_noBrokerSelector_shouldRevert() public {
    address wrongExchangeProvider = makeAddr("wrongExchangeProvider");
    vm.expectRevert();
    factory.deployVirtualPool(wrongExchangeProvider, bytes32(0));
  }

  function test_deployPool_whenWrongExchangeProvider_noBroker_shouldRevert() public {
    address wrongExchangeProvider = makeAddr("wrongExchangeProvider");
    vm.mockCall(wrongExchangeProvider, abi.encodeWithSelector(IBiPoolManager.broker.selector), abi.encode(address(0)));
    vm.expectRevert();
    factory.deployVirtualPool(wrongExchangeProvider, bytes32(0));
  }

  function test_deployPool_whenWrongExchangeProvider_noExchanges_shouldRevert() public {
    address wrongExchangeProvider = makeAddr("wrongExchangeProvider");
    address fakeBroker = makeAddr("fakeBroker");
    vm.mockCall(wrongExchangeProvider, abi.encodeWithSelector(IBiPoolManager.broker.selector), abi.encode(fakeBroker));
    vm.expectRevert();
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
    vm.prank(governance);
    factory.deployVirtualPool(wrongExchangeProvider, bytes32(0));
  }

  function test_deployPool_shouldEmitEventAndSavePool() public {
    (address t0, address t1) = (tokenA < tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
    address precomputedAddress = factory.getOrPrecomputeProxyAddress(t0, t1);
    vm.prank(governance);
    vm.expectEmit();
    emit VirtualPoolDeployed(precomputedAddress, t0, t1);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));
    assertEq(factory.isPool(pool), true);
    assertEq(factory.getPool(tokenA, tokenB), pool);
    assertEq(factory.getPool(tokenB, tokenA), pool);
    assertEq(factory.getOrPrecomputeProxyAddress(tokenA, tokenB), pool);
    assertEq(factory.getOrPrecomputeProxyAddress(tokenB, tokenA), pool);
  }

  function test_deployPool_whenPairAlreadyExists_shouldRevert() public {
    vm.startPrank(governance);
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
    vm.stopPrank();
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

  function test_getAllPools_whenNoPools_shouldReturnEmptyArray() public view {
    address[] memory pools = factory.getAllPools();
    assertEq(pools.length, 0);
  }

  function test_getAllPools_afterDeployment_shouldReturnPool() public {
    vm.prank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    address[] memory pools = factory.getAllPools();
    assertEq(pools.length, 1);
    assertEq(pools[0], pool);
  }

  function test_getAllPools_afterMultipleDeployments_shouldReturnAllPools() public {
    address tokenC = address(new MockERC20("Token C", "TOKC", 18));
    address tokenD = address(new MockERC20("Token D", "TOKD", 18));

    vm.prank(governance);
    address pool1 = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    vm.mockCall(
      exchangeProvider,
      abi.encodeWithSelector(IBiPoolManager.exchanges.selector, bytes32(uint256(1))),
      abi.encode(_makeQuickExchange(tokenC, tokenD))
    );

    vm.prank(governance);
    address pool2 = factory.deployVirtualPool(exchangeProvider, bytes32(uint256(1)));

    address[] memory pools = factory.getAllPools();
    assertEq(pools.length, 2);
    assertTrue(pools[0] == pool1 || pools[1] == pool1);
    assertTrue(pools[0] == pool2 || pools[1] == pool2);
  }

  /* ============================================================ */
  /* ==================== Deprecation Tests ===================== */
  /* ============================================================ */

  function test_deprecatePool_whenNotOwner_shouldRevert() public {
    vm.prank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    vm.prank(makeAddr("literallyAnyone"));
    vm.expectRevert("Ownable: caller is not the owner");
    factory.deprecatePool(pool);
  }

  function test_deprecatePool_whenPoolNotFound_shouldRevert() public {
    address fakePool = makeAddr("fakePool");

    vm.prank(governance);
    vm.expectRevert(IVirtualPoolFactory.PoolNotFound.selector);
    factory.deprecatePool(fakePool);
  }

  function test_deprecatePool_whenAlreadyDeprecated_shouldRevert() public {
    vm.startPrank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));
    factory.deprecatePool(pool);

    vm.expectRevert(IVirtualPoolFactory.PoolAlreadyDeprecated.selector);
    factory.deprecatePool(pool);
    vm.stopPrank();
  }

  function test_deprecatePool_shouldEmitEvent() public {
    vm.prank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    vm.prank(governance);
    vm.expectEmit();
    emit PoolDeprecated(pool);
    factory.deprecatePool(pool);
  }

  function test_deprecatePool_shouldExcludeFromGetAllPools() public {
    vm.prank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    assertEq(factory.getAllPools().length, 1);

    vm.prank(governance);
    factory.deprecatePool(pool);

    assertEq(factory.getAllPools().length, 0);
  }

  function test_isPool_whenDeprecated_shouldReturnFalse() public {
    vm.prank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    assertEq(factory.isPool(pool), true);

    vm.prank(governance);
    factory.deprecatePool(pool);

    assertEq(factory.isPool(pool), false);
  }

  function test_isPoolDeprecated_whenDeprecated_shouldReturnTrue() public {
    vm.prank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    vm.prank(governance);
    factory.deprecatePool(pool);

    assertEq(factory.isPoolDeprecated(pool), true);
  }

  function test_deprecatedPool_shouldStillBeAccessibleViaGetPool() public {
    vm.prank(governance);
    address pool = factory.deployVirtualPool(exchangeProvider, bytes32(0));

    vm.prank(governance);
    factory.deprecatePool(pool);

    // getPool should still return the pool address
    assertEq(factory.getPool(tokenA, tokenB), pool);
    assertEq(factory.getPool(tokenB, tokenA), pool);
  }
}
