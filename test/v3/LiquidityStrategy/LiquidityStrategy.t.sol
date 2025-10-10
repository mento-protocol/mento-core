// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase, var-name-mixedcase, state-visibility
// solhint-disable const-name-snakecase, max-states-count, contract-name-camelcase
pragma solidity ^0.8;

import { LiquidityStrategy_BaseTest } from "./LiquidityStrategy_BaseTest.sol";
import { LiquidityStrategyHarness } from "test/utils/harnesses/LiquidityStrategyHarness.sol";
import { MockFPMM } from "test/utils/mocks/MockFPMM.sol";
import { LiquidityStrategyTypes as LQ } from "contracts/v3/libraries/LiquidityStrategyTypes.sol";
import { ILiquidityStrategy } from "contracts/v3/interfaces/ILiquidityStrategy.sol";

contract LiquidityStrategy_Test is LiquidityStrategy_BaseTest {
  LiquidityStrategyHarness public strategy;

  function setUp() public override {
    super.setUp();
    strategy = new LiquidityStrategyHarness(owner);
  }

  /* ============================================================ */
  /* =================== Pool Management Tests ================== */
  /* ============================================================ */

  function test_addPool_whenValidParams_shouldAddPool() public {
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);

    vm.expectEmit(true, true, true, true);
    emit PoolAdded(address(mockPool), true, 3600, 50);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    assertTrue(strategy.isPoolRegistered(address(mockPool)));
  }

  function test_addPool_whenPoolIsZero_shouldRevert() public {
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_MUST_BE_SET.selector);
    strategy.addPool(address(0), debtToken, 3600, 50);
  }

  function test_addPool_whenIncentiveTooHigh_shouldRevert() public {
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);
    mockPool.setRebalanceIncentive(50); // Pool max is 50

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_BAD_INCENTIVE.selector);
    strategy.addPool(address(mockPool), debtToken, 3600, 100); // Trying to set 100
  }

  function test_addPool_whenPoolAlreadyExists_shouldRevert() public {
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_ALREADY_EXISTS.selector);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);
  }

  function test_addPool_whenCalledByNonOwner_shouldRevert() public {
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);

    vm.prank(notOwner);
    vm.expectRevert();
    strategy.addPool(address(mockPool), debtToken, 3600, 50);
  }

  function test_removePool_whenPoolExists_shouldRemovePool() public {
    // Add pool first
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);
    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    // Remove it
    vm.expectEmit(true, false, false, false);
    emit PoolRemoved(address(mockPool));

    vm.prank(owner);
    strategy.removePool(address(mockPool));

    assertFalse(strategy.isPoolRegistered(address(mockPool)));
  }

  function test_removePool_whenPoolDoesNotExist_shouldRevert() public {
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);

    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_POOL_NOT_FOUND.selector);
    strategy.removePool(address(mockPool));
  }

  function test_setRebalanceCooldown_whenPoolExists_shouldUpdateCooldown() public {
    // Add pool
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);
    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    // Update cooldown
    vm.expectEmit(true, false, false, true);
    emit RebalanceCooldownSet(address(mockPool), 7200);

    vm.prank(owner);
    strategy.setRebalanceCooldown(address(mockPool), 7200);
  }

  function test_setRebalanceIncentive_whenValid_shouldUpdateIncentive() public {
    // Add pool
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);
    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    // Update incentive
    vm.expectEmit(true, false, false, true);
    emit RebalanceIncentiveSet(address(mockPool), 75);

    vm.prank(owner);
    strategy.setRebalanceIncentive(address(mockPool), 75);
  }

  function test_setRebalanceIncentive_whenExceedsPoolCap_shouldRevert() public {
    // Add pool
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);
    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    // Try to set incentive above pool cap
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_BAD_INCENTIVE.selector);
    strategy.setRebalanceIncentive(address(mockPool), 150);
  }

  /* ============================================================ */
  /* ================= Determine Action Tests =================== */
  /* ============================================================ */

  function test_determineAction_expansion_isToken0Debt_poolPriceAbove() public {
    MockFPMM mockPool = _createMockFPMMForExpansion(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(mockPool));

    // Should be expansion: add debt (token0), take collateral (token1)
    assertEq(uint(action.dir), uint(LQ.Direction.Expand));
    assertTrue(action.inputAmount > 0); // Debt in
    assertEq(action.amount0Out, 0); // No debt out
    assertTrue(action.amount1Out > 0); // Collateral out
  }

  function test_determineAction_contraction_isToken0Debt_poolPriceBelow() public {
    MockFPMM mockPool = _createMockFPMMForContraction(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(mockPool));

    // Should be contraction: add collateral (token1), take debt (token0)
    assertEq(uint(action.dir), uint(LQ.Direction.Contract));
    assertTrue(action.inputAmount > 0); // Collateral in
    assertTrue(action.amount0Out > 0); // Debt out
    assertEq(action.amount1Out, 0); // No collateral out
  }

  function test_determineAction_expansion_isToken1Debt_poolPriceAbove() public {
    // Swap token order - now token1 is debt
    MockFPMM mockPool = _createMockFPMMForExpansion(collateralToken, debtToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(mockPool));

    // Should be contraction: take debt (token1) from pool, add collateral (token0)
    assertEq(uint(action.dir), uint(LQ.Direction.Contract));
    assertTrue(action.inputAmount > 0); // Collateral in
    assertTrue(action.amount1Out > 0); // Debt out (token1)
    assertEq(action.amount0Out, 0);
  }

  function test_determineAction_contraction_isToken1Debt_poolPriceBelow() public {
    // Swap token order - now token1 is debt
    MockFPMM mockPool = _createMockFPMMForContraction(collateralToken, debtToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    (LQ.Context memory ctx, LQ.Action memory action) = strategy.determineAction(address(mockPool));

    // Should be expansion: add debt (token1), take collateral (token0)
    assertEq(uint(action.dir), uint(LQ.Direction.Expand));
    assertTrue(action.inputAmount > 0); // Debt in
    assertTrue(action.amount0Out > 0); // Collateral out (token0)
    assertEq(action.amount1Out, 0);
  }

  function test_determineAction_withDifferentDecimals() public {
    // Note: MockFPMM uses 1e18 for both tokens by default
    // For now, skip this test or implement custom decimal support in MockFPMM
    // TODO: Add decimal configuration to MockFPMM
  }

  /* ============================================================ */
  /* =================== Rebalance Tests ======================== */
  /* ============================================================ */

  function test_rebalance_whenCooldownActive_shouldRevert() public {
    MockFPMM mockPool = _createMockFPMMForExpansion(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    // First rebalance
    vm.prank(owner);
    strategy.rebalance(address(mockPool));

    // Try immediate second rebalance
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_COOLDOWN_ACTIVE.selector);
    strategy.rebalance(address(mockPool));
  }

  function test_rebalance_afterCooldown_shouldSucceed() public {
    MockFPMM mockPool = _createMockFPMMForExpansion(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 3600, 50);

    // First rebalance
    vm.prank(owner);
    strategy.rebalance(address(mockPool));

    // Warp past cooldown
    vm.warp(block.timestamp + 3601);

    // Second rebalance should succeed
    vm.prank(owner);
    strategy.rebalance(address(mockPool));
  }

  function test_rebalance_shouldEmitLiquidityMovedEvent() public {
    MockFPMM mockPool = _createMockFPMMForExpansion(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 0, 50); // 0 cooldown

    // Expect LiquidityMoved event
    vm.expectEmit(true, false, false, false);
    emit LiquidityMoved(address(mockPool), LQ.Direction.Expand, 0, 0, 0); // Amounts will vary

    vm.prank(owner);
    strategy.rebalance(address(mockPool));
  }

  /* ============================================================ */
  /* ============== Hook Called Mechanism Tests ================= */
  /* ============================================================ */

  function test_rebalance_whenHookNotCalled_shouldRevert() public {
    // Create a mock FPMM but use vm.mockCall to override rebalance to NOT call hook
    MockFPMM mockPool = _createMockFPMMForExpansion(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 0, 50);

    // Mock rebalance to not trigger the callback
    vm.mockCall(address(mockPool), abi.encodeWithSelector(MockFPMM.rebalance.selector), abi.encode());

    // Should revert because hook was not called
    vm.prank(owner);
    vm.expectRevert(ILiquidityStrategy.LS_HOOK_NOT_CALLED.selector);
    strategy.rebalance(address(mockPool));
  }

  function test_rebalance_whenHookCalled_shouldSucceed() public {
    // MockFPMM properly calls the hook, so this should succeed
    MockFPMM mockPool = _createMockFPMMForExpansion(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 0, 50);

    vm.prank(owner);
    strategy.rebalance(address(mockPool));
  }

  function test_hook_whenCalledFromNonPool_shouldRevert() public {
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 0, 50);

    // Try to call hook from non-pool address
    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: 100e18,
        incentiveBps: 50,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collateralToken
      })
    );

    vm.prank(notOwner); // Not the pool
    vm.expectRevert(ILiquidityStrategy.LS_POOL_NOT_FOUND.selector);
    strategy.hook(address(strategy), 0, 100e18, hookData);
  }

  function test_hook_whenSenderIsNotStrategy_shouldRevert() public {
    MockFPMM mockPool = _createMockFPMM(debtToken, collateralToken);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 0, 50);

    bytes memory hookData = abi.encode(
      LQ.CallbackData({
        inputAmount: 100e18,
        incentiveBps: 50,
        dir: LQ.Direction.Expand,
        isToken0Debt: true,
        debtToken: debtToken,
        collateralToken: collateralToken
      })
    );

    // Call from pool but with wrong sender
    vm.prank(address(mockPool));
    vm.expectRevert(ILiquidityStrategy.LS_INVALID_SENDER.selector);
    strategy.hook(notOwner, 0, 100e18, hookData);
  }

  function test_transientStorage_shouldResetBetweenTransactions() public {
    // Use a real MockFPMM that properly simulates the callback
    MockFPMM mockPool = new MockFPMM(debtToken, collateralToken, false);
    // Set prices: oracle 1:1, reserves 1.1:1 (pool price 10% above oracle)
    mockPool.setPrices(1e18, 1e18, 110e18, 100e18, 1000, true);
    mockPool.setRebalanceIncentive(100);

    vm.prank(owner);
    strategy.addPool(address(mockPool), debtToken, 0, 50);

    // First transaction - should succeed
    vm.prank(owner);
    strategy.rebalance(address(mockPool));

    // Simulate a new transaction by:
    // 1. Advancing time to pass cooldown
    vm.warp(block.timestamp + 1);
    // 2. Manually clearing transient storage (simulates EIP-1153 automatic clearing between transactions)
    strategy.clearTransientStorage(address(mockPool));

    // Second transaction - transient storage should be cleared
    // So the hook check at the start should NOT revert with LS_CAN_ONLY_REBALANCE_ONCE
    // Instead it should work normally and succeed
    vm.prank(owner);
    strategy.rebalance(address(mockPool));
  }

  function test_rebalance_multiplePools_shouldTrackSeparately() public {
    // Create two real MockFPMM instances
    MockFPMM mockPool1 = new MockFPMM(debtToken, collateralToken, false);
    mockPool1.setPrices(1e18, 1e18, 110e18, 100e18, 1000, true); // Pool price 10% above oracle
    mockPool1.setRebalanceIncentive(100);

    MockFPMM mockPool2 = new MockFPMM(debtToken, collateralToken, false);
    mockPool2.setPrices(1e18, 1e18, 110e18, 100e18, 1000, true); // Pool price 10% above oracle
    mockPool2.setRebalanceIncentive(100);

    vm.startPrank(owner);
    strategy.addPool(address(mockPool1), debtToken, 0, 50);
    strategy.addPool(address(mockPool2), debtToken, 0, 50);

    // Should be able to rebalance both pools in the same transaction
    // Each pool tracks its own transient storage flag
    strategy.rebalance(address(mockPool1));
    strategy.rebalance(address(mockPool2));
    vm.stopPrank();
  }
}
