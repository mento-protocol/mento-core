// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
// solhint-disable modifier-name-mixedcase,
pragma solidity ^0.8;
import { Test } from "mento-std/Test.sol";

import { IFPMM } from "contracts/interfaces/IFPMM.sol";

import { MockLiquidityStrategy } from "test/utils/mocks/MockLiquidityStrategy.sol";
import { MockERC20 } from "test/utils/mocks/MockERC20.sol";

contract LiquidityStrategyTest is Test {
  address public deployer = makeAddr("deployer");

  MockLiquidityStrategy public mockConcreteLiquidityStrat;
  MockERC20 mockToken0;
  MockERC20 mockToken1;
  address mockPool;

  event FPMMPoolAdded(address indexed pool, uint256 rebalanceCooldown);
  event FPMMPoolRemoved(address indexed pool);
  event RebalanceSkippedNotCool(address indexed pool);
  event RebalanceSkippedPriceInRange(address indexed pool);
  event RebalanceExecuted(address indexed pool, uint256 priceBefore, uint256 priceAfter);

  function setUp() public {
    vm.startPrank(deployer);
    mockConcreteLiquidityStrat = new MockLiquidityStrategy();
    mockConcreteLiquidityStrat.initialize();
    createMockPool();
  }

  /* ---------- Add Pool ---------- */

  function test_addPool_shouldRevert_whenPoolIsZeroAddress() public {
    vm.expectRevert("LS: INVALID_POOL_ADDRESS");
    mockConcreteLiquidityStrat.addPool(address(0), 1 days);
  }

  function test_addPool_shouldRevert_whenCooldownIsZero() public {
    vm.expectRevert("LS: ZERO_COOLDOWN_PERIOD");
    mockConcreteLiquidityStrat.addPool(address(1), 0);
  }

  function test_addPool_shouldRevert_whenPoolIsAlreadyAdded() public {
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
    vm.expectRevert("LS: POOL_ALREADY_ADDED");
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
  }

  function test_addPool_shouldRevert_whenCallerNotOwner() public {
    vm.stopPrank();
    vm.expectRevert("Ownable: caller is not the owner");
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
  }

  function test_addPool_shouldRevert_whenTokenDecimalsGreaterThan18() public {
    // Token 0 has 19 decimals
    vm.mockCall(address(mockToken0), abi.encodeWithSelector(MockERC20.decimals.selector), abi.encode(19));

    vm.expectRevert("LS: TOKEN_DECIMALS_TOO_LARGE");
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);

    // Token 1 has 19 decimals & Token 0 has 18 decimals
    vm.mockCall(address(mockToken0), abi.encodeWithSelector(MockERC20.decimals.selector), abi.encode(18));
    vm.mockCall(address(mockToken1), abi.encodeWithSelector(MockERC20.decimals.selector), abi.encode(19));

    vm.expectRevert("LS: TOKEN_DECIMALS_TOO_LARGE");
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
  }

  function test_addPool_shouldEmitEventAndSetTokenPrecisionMultipliers_WhenPoolIsAdded() public {
    vm.expectEmit(true, true, true, true);
    emit FPMMPoolAdded(address(mockPool), 1 days);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);

    assertEq(mockConcreteLiquidityStrat.tokenPrecisionMultipliers(address(mockToken0)), 1);
    assertEq(mockConcreteLiquidityStrat.tokenPrecisionMultipliers(address(mockToken1)), 1);
  }

  /* ---------- Remove Pool ---------- */

  function test_removePool_shouldRevert_whenPoolIsNotAdded() public {
    vm.expectRevert("LS: UNREGISTERED_POOL");
    mockConcreteLiquidityStrat.removePool(address(mockPool));
  }

  function test_removePool_shouldEmitEvent_WhenPoolIsRemoved() public {
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
    vm.expectEmit(true, true, true, true);
    emit FPMMPoolRemoved(address(mockPool));
    mockConcreteLiquidityStrat.removePool(address(mockPool));
  }

  function test_removePool_shouldRevert_whenCallerNotOwner() public {
    vm.stopPrank();
    vm.expectRevert("Ownable: caller is not the owner");
    mockConcreteLiquidityStrat.removePool(address(mockPool));
  }

  /* ---------- Rebalance ---------- */

  function test_rebalance_shouldRevert_whenPoolIsNotAdded() public {
    vm.expectRevert("LS: UNREGISTERED_POOL");
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldReturnAndEmitEvent_WhenRecentlyRebalanced() public {
    // Set oracle price and pool price with diff bigger than threshold
    setPoolPrices(1000, 1);

    // Trigger the first rebalance
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
    vm.warp(1 days + 1);

    vm.expectEmit(true, true, true, true);
    emit RebalanceSkippedNotCool(address(mockPool));

    // Try to rebalance again without any time being passed
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenThresholdIsZero() public {
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThreshold.selector), abi.encode(0));
    vm.expectRevert("LS: INVALID_THRESHOLD");
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenThresholdIsTooHigh() public {
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThreshold.selector), abi.encode(10001));
    vm.expectRevert("LS: INVALID_THRESHOLD");
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldReturnAndEmitEvent_WhenPoolPriceIsWithinThreshold() public {
    setPoolPrices(1e18, 0.95e18);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);

    vm.expectEmit(true, true, true, true);
    emit RebalanceSkippedPriceInRange(address(mockPool));

    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldUpdateLastRebalanceAndEmitEvent_WhenPoolPriceIsAboveThreshold() public {
    rebalanceWithPriceOutsideThreshold(1.06e18, 1e18);
  }

  function test_rebalance_shouldUpdateLastRebalanceAndEmitEvent_WhenPoolPriceIsBelowThreshold() public {
    rebalanceWithPriceOutsideThreshold(0.94e18, 1e18);
  }

  /* ==================== Test Helpers ==================== */

  function createMockPool() private {
    mockPool = makeAddr("mockPool");
    mockToken0 = new MockERC20("Mock Token 0", "MT0", 18);
    mockToken1 = new MockERC20("Mock Token 1", "MT1", 18);

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.token0.selector), abi.encode(address(mockToken0)));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.token1.selector), abi.encode(address(mockToken1)));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThreshold.selector), abi.encode(500));

    setPoolPrices(1000, 1000);
  }

  function setPoolPrices(uint256 oraclePrice, uint256 poolPrice) private {
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IFPMM.getPrices.selector),
      abi.encode(oraclePrice, poolPrice)
    );
  }

  function rebalanceWithPriceOutsideThreshold(uint256 poolPrice, uint256 oraclePrice) private {
    setPoolPrices(oraclePrice, poolPrice);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days);

    vm.warp(123456);
    vm.expectEmit(true, true, true, true);

    // In this case, there is no price change because mock strategy is not doing anything
    // so the price before and after rebalance is the same.
    // For this test, we don't care about the price change, we just want to test that the last rebalance is updated.
    // and that the event is emitted with the correct numbers (pool price before and after rebalance).
    emit RebalanceExecuted(address(mockPool), poolPrice, poolPrice);
    mockConcreteLiquidityStrat.rebalance(address(mockPool));

    (uint256 lastRebalance, ) = mockConcreteLiquidityStrat.fpmmPoolConfigs(address(mockPool));
    assertEq(lastRebalance, 123456);
  }
}
