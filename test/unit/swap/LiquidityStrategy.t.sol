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
  address public nonOwner = makeAddr("nonOwner");

  MockLiquidityStrategy public mockConcreteLiquidityStrat;
  MockERC20 mockToken0;
  MockERC20 mockToken1;
  address mockPool;

  event FPMMPoolAdded(address indexed pool, uint256 rebalanceCooldown, uint256 rebalanceIncentive);
  event FPMMPoolRemoved(address indexed pool);
  event RebalanceExecuted(address indexed pool, uint256 priceBefore, uint256 priceAfter);
  event RebalanceIncentiveSet(address indexed pool, uint256 rebalanceIncentive);
  event RebalanceCooldownSet(address indexed pool, uint256 rebalanceCooldown);
  event Withdraw(address indexed tokenAddress, address indexed recipient, uint256 amount);

  function setUp() public {
    vm.startPrank(deployer);
    mockConcreteLiquidityStrat = new MockLiquidityStrategy();
    mockConcreteLiquidityStrat.initialize();
    createMockPool();
    vm.stopPrank();
  }

  /* ---------- Add Pool ---------- */

  function test_addPool_shouldRevert_whenPoolIsZeroAddress() public {
    vm.prank(deployer);
    vm.expectRevert("LS: INVALID_POOL_ADDRESS");
    mockConcreteLiquidityStrat.addPool(address(0), 1 days, 100);
  }

  function test_addPool_shouldRevert_whenPoolIsAlreadyAdded() public {
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
    vm.prank(deployer);
    vm.expectRevert("LS: POOL_ALREADY_ADDED");
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
  }

  function test_addPool_shouldRevert_whenRebalanceIncentiveIsInvalid() public {
    vm.prank(deployer);
    vm.expectRevert("LS: INVALID_REBALANCE_INCENTIVE");
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 101);
  }

  function test_addPool_shouldRevert_whenCallerNotOwner() public {
    vm.prank(nonOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
  }

  function test_addPool_shouldEmitEvent_whenPoolIsAdded() public {
    vm.expectEmit(true, true, true, true);
    emit FPMMPoolAdded(address(mockPool), 1 days, 100);
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
  }

  /* ---------- Remove Pool ---------- */

  function test_removePool_shouldRevert_whenPoolIsNotAdded() public {
    vm.prank(deployer);
    vm.expectRevert("LS: UNREGISTERED_POOL");
    mockConcreteLiquidityStrat.removePool(address(mockPool));
  }

  function test_removePool_shouldEmitEvent_whenPoolIsRemoved() public {
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
    vm.expectEmit(true, true, true, true);
    emit FPMMPoolRemoved(address(mockPool));
    vm.prank(deployer);
    mockConcreteLiquidityStrat.removePool(address(mockPool));
  }

  function test_removePool_shouldRevert_whenCallerNotOwner() public {
    vm.prank(makeAddr("nonOwner"));
    vm.expectRevert("Ownable: caller is not the owner");
    mockConcreteLiquidityStrat.removePool(address(mockPool));
  }

  /* ---------- Set Rebalance Incentive ---------- */

  function test_setRebalanceIncentive_shouldRevert_whenCallerNotOwner() public {
    vm.prank(nonOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    mockConcreteLiquidityStrat.setRebalanceIncentive(address(mockPool), 100);
  }

  function test_setRebalanceIncentive_shouldRevert_whenPoolIsNotAdded() public {
    vm.prank(deployer);
    vm.expectRevert("LS: UNREGISTERED_POOL");
    mockConcreteLiquidityStrat.setRebalanceIncentive(address(mockPool), 100);
  }

  function test_setRebalanceIncentive_shouldRevert_whenRebalanceIncentiveIsInvalid() public {
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);

    vm.prank(deployer);
    vm.expectRevert("LS: INVALID_REBALANCE_INCENTIVE");
    mockConcreteLiquidityStrat.setRebalanceIncentive(address(mockPool), 101);
  }

  function test_setRebalanceIncentive_shouldEmitEvent_whenRebalanceIncentiveIsSet() public {
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
    vm.expectEmit(true, true, true, true);
    emit RebalanceIncentiveSet(address(mockPool), 100);
    vm.prank(deployer);
    mockConcreteLiquidityStrat.setRebalanceIncentive(address(mockPool), 100);
  }

  /* ---------- Withdraw ---------- */

  function test_withdraw_shouldRevert_whenTokenAddressIsZeroAddress() public {
    vm.prank(deployer);
    vm.expectRevert("LS: INVALID_TOKEN_ADDRESS");
    mockConcreteLiquidityStrat.withdraw(address(0), address(deployer));
  }

  function test_withdraw_shouldRevert_whenRecipientIsZeroAddress() public {
    vm.prank(deployer);
    vm.expectRevert("LS: INVALID_RECIPIENT_ADDRESS");
    mockConcreteLiquidityStrat.withdraw(address(mockToken0), address(0));
  }

  function test_withdraw_shouldRevert_whenNoTokensToWithdraw() public {
    vm.prank(deployer);
    vm.expectRevert("LS: NO_TOKENS_TO_WITHDRAW");
    mockConcreteLiquidityStrat.withdraw(address(mockToken0), address(deployer));
  }

  function test_withdraw_shouldTransferTokens_whenTokensToWithdraw() public {
    uint256 initialBalance = 100e18;
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);

    vm.prank(deployer);
    mockToken0.mint(address(mockConcreteLiquidityStrat), initialBalance);

    vm.prank(deployer);
    vm.expectEmit(true, true, true, true);
    emit Withdraw(address(mockToken0), address(deployer), initialBalance);
    mockConcreteLiquidityStrat.withdraw(address(mockToken0), address(deployer));

    assertEq(mockToken0.balanceOf(address(deployer)), initialBalance);
    assertEq(mockToken0.balanceOf(address(mockConcreteLiquidityStrat)), 0);
  }

  /* ---------- Set Rebalance Cooldown ---------- */

  function test_setRebalanceCooldown_shouldRevert_whenCallerNotOwner() public {
    vm.prank(nonOwner);
    vm.expectRevert("Ownable: caller is not the owner");
    mockConcreteLiquidityStrat.setRebalanceCooldown(address(mockPool), 1 days);
  }

  function test_setRebalanceCooldown_shouldRevert_whenPoolIsNotAdded() public {
    vm.prank(deployer);
    vm.expectRevert("LS: UNREGISTERED_POOL");
    mockConcreteLiquidityStrat.setRebalanceCooldown(address(mockPool), 1 days);
  }

  function test_setRebalanceCooldown_shouldEmitEvent_whenRebalanceCooldownIsSet() public {
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
    vm.expectEmit(true, true, true, true);
    emit RebalanceCooldownSet(address(mockPool), 1 days);
    vm.prank(deployer);
    mockConcreteLiquidityStrat.setRebalanceCooldown(address(mockPool), 1 days);
  }

  /* ---------- Rebalance ---------- */

  function test_rebalance_shouldRevert_whenPoolIsNotAdded() public {
    vm.expectRevert("LS: UNREGISTERED_POOL");
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenCooldownActive() public {
    // Set oracle price and pool price with diff bigger than threshold
    setPoolPrices(1e18, 1e18, 2e18, 1e18, 10_000, true);

    // Trigger the first rebalance
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);

    vm.prank(nonOwner);
    mockConcreteLiquidityStrat.rebalance(address(mockPool));

    // Warp forward but not enough to satisfy the cooldown (1 day + 1 second)
    vm.warp(block.timestamp + 1);

    // Try to rebalance again before cooldown is satisfied
    vm.expectRevert("LS: COOLDOWN_ACTIVE");
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenUpperThresholdIsInvalid() public {
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);

    // Test 0 threshold
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThresholdAbove.selector), abi.encode(0));
    vm.expectRevert("LS: INVALID_UPPER_THRESHOLD");
    vm.prank(nonOwner);
    mockConcreteLiquidityStrat.rebalance(address(mockPool));

    // Test threshold > 10000
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThresholdAbove.selector), abi.encode(10001));
    vm.expectRevert("LS: INVALID_UPPER_THRESHOLD");
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenLowerThresholdIsInvalid() public {
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThresholdAbove.selector), abi.encode(100));

    // Test 0 threshold
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThresholdBelow.selector), abi.encode(0));
    vm.expectRevert("LS: INVALID_LOWER_THRESHOLD");
    vm.prank(nonOwner);
    mockConcreteLiquidityStrat.rebalance(address(mockPool));

    // Test threshold > 10000
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThresholdBelow.selector), abi.encode(10001));
    vm.expectRevert("LS: INVALID_LOWER_THRESHOLD");
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldRevert_whenPoolPriceIsWithinThreshold() public {
    // pool price 1, reserve price 1.01
    setPoolPrices(1e18, 1e18, 101e16, 1e18, 0, true);
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);

    vm.expectRevert("LS: PRICE_IN_RANGE");
    vm.prank(nonOwner);
    mockConcreteLiquidityStrat.rebalance(address(mockPool));
  }

  function test_rebalance_shouldUpdateLastRebalanceAndEmitEvent_whenPoolPriceIsAboveThreshold() public {
    // oraclePrice = 1.1, poolPrice = 2
    rebalanceWithPriceOutsideThreshold(11e17, 1e18, 2e18, 1e18, 8181, true);
  }

  function test_rebalance_shouldUpdateLastRebalanceAndEmitEvent_whenPoolPriceIsBelowThreshold() public {
    // oraclePrice = 2, poolPrice = 1.1
    rebalanceWithPriceOutsideThreshold(2e18, 1e18, 11e17, 1e18, 8181, false);
  }

  /* ==================== Test Helpers ==================== */

  function createMockPool() private {
    mockPool = makeAddr("mockPool");
    mockToken0 = new MockERC20("Mock Token 0", "MT0", 18);
    mockToken1 = new MockERC20("Mock Token 1", "MT1", 18);

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.token0.selector), abi.encode(address(mockToken0)));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.token1.selector), abi.encode(address(mockToken1)));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThresholdAbove.selector), abi.encode(500));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceThresholdBelow.selector), abi.encode(500));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IFPMM.rebalanceIncentive.selector), abi.encode(100));

    setPoolPrices(1e18, 1e18, 1000e18, 1000e18, 0, false);
  }

  function setPoolPrices(
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    uint256 poolPriceNumerator,
    uint256 poolPriceDenominator,
    uint256 priceDifference,
    bool reservePriceAboveOraclePrice
  ) private {
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IFPMM.getPrices.selector),
      abi.encode(
        oraclePriceNumerator,
        oraclePriceDenominator,
        poolPriceNumerator,
        poolPriceDenominator,
        priceDifference,
        reservePriceAboveOraclePrice
      )
    );
  }

  function rebalanceWithPriceOutsideThreshold(
    uint256 oraclePriceNumerator,
    uint256 oraclePriceDenominator,
    uint256 poolPriceDenominator,
    uint256 poolPriceNumerator,
    uint256 priceDifference,
    bool reservePriceAboveOraclePrice
  ) private {
    setPoolPrices(
      oraclePriceNumerator,
      oraclePriceDenominator,
      poolPriceNumerator,
      poolPriceDenominator,
      priceDifference,
      reservePriceAboveOraclePrice
    );
    vm.prank(deployer);
    mockConcreteLiquidityStrat.addPool(address(mockPool), 1 days, 100);

    vm.warp(123456);
    vm.expectEmit(true, true, true, true);

    // In this case, there is no price change because mock strategy is not doing anything
    // so the price before and after rebalance is the same.
    // For this test, we don't care about the price change, we just want to test that the last rebalance is updated.
    // and that the event is emitted with the correct numbers (pool price before and after rebalance).
    emit RebalanceExecuted(address(mockPool), priceDifference, priceDifference);
    vm.prank(nonOwner);
    mockConcreteLiquidityStrat.rebalance(address(mockPool));

    (uint256 lastRebalance, , ) = mockConcreteLiquidityStrat.fpmmPoolConfigs(address(mockPool));
    assertEq(lastRebalance, 123456);
  }
}
